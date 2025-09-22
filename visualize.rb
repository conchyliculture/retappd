require 'sinatra'
require 'sqlite3'
require 'timezone_finder'
require "tzinfo"
require 'json'
require 'slim'

require 'sinatra/reloader'

configure do
  if ENV['RETAPPD_ALLOWED_HOSTS']
    allowed_hosts = ENV['RETAPPD_ALLOWED_HOSTS'].split(",")
    set :host_authorization, { permitted_hosts: allowed_hosts }
  end
  set :bind, '0.0.0.0'
  set :database, ENV['RETAPPED_SQLITE_DB_PATH'] || 'data/retappd.sqlite'
  set :tz_finder, TimezoneFinder.create
  set :home_coords, { lat: (ENV['RETAPPD_HOME_LAT'] || 50.8467).to_f, lng: (ENV['RETAPPD_HOME_LAT'] || 4.3525).to_f }
end

unless File.exist?(settings.database)
  raise StandardError, "No database file found at #{settings.database}"
end

def db
  @db ||= SQLite3::Database.new(settings.database)
  @db.results_as_hash = true
  @db
end

# Main dashboard route
get '/' do
  @title = "Beer Dashboard"
  if ENV['RETAPPD_USERNAME']
    @title = "#{ENV['RETAPPD_USERNAME']}'s #{@title}"
  end
  slim :dashboard
end

# API endpoints for statistics
get '/api/stats' do
  content_type :json

  stats = {
    total_checkins: db.execute("SELECT COUNT(*) as count FROM checkin")[0]['count'],
    unique_beers: db.execute("SELECT COUNT(DISTINCT beer_id) as count FROM checkin")[0]['count'],
    total_breweries: db.execute("SELECT COUNT(*) as count FROM brewery")[0]['count'],
    beer_styles: db.execute("SELECT COUNT(DISTINCT style) as count FROM beer WHERE style IS NOT NULL")[0]['count'],
    average_rating: db.execute("SELECT ROUND(AVG(rating_score), 2) as avg FROM checkin WHERE rating_score IS NOT NULL")[0]['avg'],
    venues: db.execute("SELECT COUNT(*) as count FROM venue")[0]['count'],
    cities: get_unique_cities_count,
    countries: get_unique_countries_count
  }

  stats.to_json
end

get '/api/top_beers' do
  content_type :json
  sort_by = params[:sort] || 'rating'

  order_clause = case sort_by
                 when 'last_checkin'
                   'ORDER BY MAX(c.created_at) DESC, avg_rating DESC'
                 else
                   'ORDER BY avg_rating DESC, checkin_count DESC'
                 end

  beers = db.execute("
    SELECT
      b.name,
      br.contact_json as brewery_contact,
      br.id as brewery_id,
      br.name as brewery,
      b.slug as beer_slug,
      b.id as beer_id,
      AVG(c.rating_score) as avg_rating,
      COUNT(c.id) as checkin_count,
      MAX(c.created_at) as last_checkin
    FROM beer b
    JOIN brewery br ON b.brewery_id = br.id
    JOIN checkin c ON b.id = c.beer_id
    WHERE c.rating_score IS NOT NULL
    GROUP BY b.id
    #{order_clause}
  ")

  res = beers.map { |beer|
    if beer['brewery_contact']
      bj = JSON.parse(beer['brewery_contact'])
      beer['brewery_url'] = bj['url']
      beer['url'] = "https://untappd.com/b/#{beer['beer_slug']}/#{beer['beer_id']}"
    end
    beer
  }.to_json
  res
end

get '/api/abv_distribution' do
  content_type :json

  abv_data = db.execute("
    SELECT
      CASE
        WHEN abv < 1 THEN '<1%'
        WHEN abv < 2 THEN '1%'
        WHEN abv < 3 THEN '2%'
        WHEN abv < 4 THEN '3%'
        WHEN abv < 5 THEN '4%'
        WHEN abv < 6 THEN '5%'
        WHEN abv < 7 THEN '6%'
        WHEN abv < 8 THEN '7%'
        WHEN abv < 9 THEN '8%'
        WHEN abv < 10 THEN '9%'
        WHEN abv < 11 THEN '10%'
        WHEN abv < 12 THEN '11%'
        ELSE '12%+'
      END as abv_range,
      COUNT(*) as count
    FROM beer b
    JOIN checkin c ON b.id = c.beer_id
    WHERE b.abv IS NOT NULL
    GROUP BY abv_range
    ORDER BY MIN(abv)
  ")

  abv_data.to_json
end

get '/api/checkins_by_hour' do
  content_type :json
  hourly_data = Hash.new(0)

  db.execute("
    SELECT
      created_at,
      venue_id
    FROM checkin
    WHERE created_at IS NOT NULL
  ").each do |row|
    next unless row['venue_id']

    venue = db.execute("SELECT * FROM venue WHERE id = ?", row['venue_id']).first
    next unless venue['location_json']

    location = JSON.parse(venue['location_json'])
    if venue['id'] == 9_917_985 or venue['name'] == "Untappd at Home"
      lat = settings.home_coords[:lat]
      lng = settings.home_coords[:lng]
    else
      lng = location['lng']
      lat = location['lat']
    end
    tz_string = settings.tz_finder.timezone_at(lng: lng, lat: lat)
    unless tz_string
      puts "Couldnot find tz for #{row} "
      raise StandardError, "Couldnot find tz for #{row}"
    end
    tz = TZInfo::Timezone.get(tz_string)
    adjusted_time = tz.to_local(Time.parse(row['created_at']))
    hour = adjusted_time.strftime('%H')
    hourly_data[hour] += 1
    if hour.to_i == 8
      puts "#{row['id']} created_at #{row['created_at']}, venue is #{venue['name']} in #{location['venue_country']} (tz is #{tz_string}) so ajusted is #{adjusted_time}"
    end
    # else
    #hourly_data[Time.parse(row['created_at']).strftime('%H')] += 1
  end

  result = []
  "00".upto("24").each do |h|
    result << { "hour" => h, "count" => hourly_data[h] }
  end

  result.to_json
end

get '/api/checkins_by_day' do
  content_type :json

  daily_data = db.execute("
    SELECT
      CASE strftime('%w', created_at)
        WHEN '0' THEN 'Sunday'
        WHEN '1' THEN 'Monday'
        WHEN '2' THEN 'Tuesday'
        WHEN '3' THEN 'Wednesday'
        WHEN '4' THEN 'Thursday'
        WHEN '5' THEN 'Friday'
        WHEN '6' THEN 'Saturday'
      END as day_name,
      COUNT(*) as count
    FROM checkin
    WHERE created_at IS NOT NULL
    GROUP BY strftime('%w', created_at)
    ORDER BY strftime('%w', created_at)
  ")

  daily_data.to_json
end

get '/api/rating_distribution' do
  content_type :json

  rating_data = db.execute("
    SELECT
      rating_score as rating,
      COUNT(*) as count
    FROM checkin
    WHERE rating_score IS NOT NULL
    GROUP BY rating_score
    ORDER BY rating
  ")

  res = []
  (0..5).step(0.25).each do |r|
    rc = rating_data.select { |e| e['rating'].to_f == r }[0]
    if rc
      res << { "rating" => r, "count" => rc['count'] }
    else
      res << { "rating" => r, "count" => 0 }
    end
  end

  res.to_json
end

get '/api/beer_styles' do
  content_type :json

  styles = db.execute("
    SELECT b.style, COUNT(c.id) as count
    FROM beer b
    JOIN checkin c ON b.id = c.beer_id
    WHERE b.style IS NOT NULL
    GROUP BY b.style
    ORDER BY count DESC
    LIMIT 10
  ")

  styles.to_json
end

get '/api/top_breweries' do
  content_type :json

  breweries = db.execute("
    SELECT br.name, COUNT(c.id) as checkin_count
    FROM brewery br
    JOIN beer b ON br.id = b.brewery_id
    JOIN checkin c ON b.id = c.beer_id
    GROUP BY br.id
    ORDER BY checkin_count DESC
    LIMIT 10
  ")

  breweries.to_json
end

get '/api/top_cities' do
  content_type :json

  get_top_venue_cities.to_json
end

get '/api/top_venues' do
  content_type :json

  venues = db.execute("
    SELECT v.name, COUNT(c.id) as checkin_count
    FROM venue v
    JOIN checkin c ON v.id = c.venue_id
    WHERE v.name != 'Untappd at Home'
    GROUP BY v.id
    ORDER BY checkin_count DESC
    LIMIT 10
  ")

  venues.to_json
end

get '/api/breweries_map' do
  content_type :json

  breweries = db.execute("
    SELECT brewery.id, brewery.name, brewery.page_url, brewery.location_json, brewery.contact_json, COUNT(brewery.id) as beer_count
    FROM brewery
    JOIN beer ON brewery.id = beer.brewery_id
    WHERE brewery.location_json IS NOT NULL
    GROUP BY brewery.id
  ")
  breweries_with_coords = breweries.map do |brewery|
    location = JSON.parse(brewery['location_json'])

    next unless location['lat'] && location['lng']
    next if location['lat'].to_i == 0 and location['lng'].to_i == 0

    url = brewery['page_url']

    begin
      contact = JSON.parse(brewery['contact_json'])

      url = contact['url']
    rescue StandardError
    end

    {
      id: brewery['id'],
      name: brewery['name'],
      lat: location['lat'],
      lng: location['lng'],
      url: url,
      checkin_count: brewery['beer_count']
    }
  end.compact

  breweries_with_coords.to_json
end

get '/api/venues_map' do
  content_type :json

  venues = db.execute("
    SELECT v.id, v.name, v.location_json, v.contact_json, COUNT(c.id) as checkin_count
    FROM venue v
    JOIN checkin c ON v.id = c.venue_id
    WHERE v.location_json IS NOT NULL
    GROUP BY v.id
  ")

  venues_with_coords = venues.map do |venue|
    location = JSON.parse(venue['location_json'])
    next if venue['name'] == "Untappd at Home"

    next unless location['lat'] && location['lng']

    url = "https://www.google.com/search?q=#{venue['name']}"
    begin
      contact = JSON.parse(venue['contact_json'])

      url = contact['venue_url'] unless url.empty?
    rescue StandardError
    end

    {
      id: venue['id'],
      name: venue['name'],
      lat: location['lat'],
      lng: location['lng'],
      url: url,
      checkin_count: venue['checkin_count']
    }
  end.compact

  venues_with_coords.to_json
end

get '/api/venue_checkins/:venue_id' do
  content_type :json
  venue_id = params[:venue_id]

  checkins = db.execute("
      SELECT
        c.id,
        c.created_at,
        c.rating_score,
        c.comment,
        b.id as beer_id,
        b.name as beer_name,
        b.slug as beer_slug,
        br.name as brewery_name,
        br.contact_json as brewery_contact,
        v.name as venue_name
      FROM checkin c
      JOIN beer b ON c.beer_id = b.id
      JOIN brewery br ON b.brewery_id = br.id
      JOIN venue v ON c.venue_id = v.id
      WHERE c.venue_id = ?
      ORDER BY c.created_at DESC
    ", [venue_id])
  res = checkins.map { |checkin|
    cj = JSON.parse(checkin['brewery_contact'])
    checkin['brewery_url'] = cj['url']
    checkin['beer_url'] = "https://untappd.com/b/#{checkin['beer_slug']}/#{checkin['beer_id']}"
    checkin
  }

  res.to_json
end

get '/api/beer_checkins/:beer_id' do
  content_type :json
  beer_id = params[:beer_id].to_i

  venues = db.execute("
      SELECT
        v.id,
        v.name as venue_name,
        v.location_json,
        COUNT(c.id) as checkin_count,
        AVG(c.rating_score) as avg_rating,
        MAX(c.created_at) as last_checkin
      FROM checkin c
      JOIN beer b ON c.beer_id = b.id
      JOIN venue v ON c.venue_id = v.id
      AND c.venue_id IS NOT NULL
      WHERE b.id = ?
      GROUP BY v.id, v.name, v.location_json
      ORDER BY checkin_count DESC, last_checkin DESC
    ", [beer_id])

  venues.to_json
end

private

def get_unique_cities_count
  venues = db.execute("SELECT location_json FROM venue WHERE location_json IS NOT NULL")
  cities = Set.new

  venues.each do |venue|
    location = JSON.parse(venue['location_json'])
    cities.add(location['venue_city']) if location['venue_city']
  end

  cities.size
end

def get_unique_countries_count
  venues = db.execute("SELECT location_json FROM venue WHERE location_json IS NOT NULL")
  countries = Set.new

  venues.each do |venue|
    location = JSON.parse(venue['location_json'])

    countries.add(location['venue_country']) if location['venue_country']
  end

  countries.size
end

def get_top_venue_cities
  venues = db.execute("
    SELECT v.location_json, COUNT(c.id) as checkin_count
    FROM venue v
    JOIN checkin c ON v.id = c.venue_id
    WHERE v.location_json IS NOT NULL
    GROUP BY v.id
  ")

  city_counts = Hash.new(0)

  venues.each do |venue|
    location = JSON.parse(venue['location_json'])

    next unless location['venue_city']
    next if location['venue_city'] == ""

    if location['venue_country'] == "日本"
      trans = {
        "渋谷区" => "Shibuya",
        "Shibuya City" => "Shibuya",
        "日光市" => "Nikko",
        "奈良市" => "Nara",
        "台東区" => "Taito",
        "鎌倉市" => "Kamakura",
        "京都市" => "kyoto",
        "東京" => "Tokyo",
        "山形市" => "Yamagata",
        "大阪市" => "Osaka",
        "姫路市" => "Himeji",
        "仙台市" => "Sendai"
      }
      location['venue_city'] = trans[location['venue_city']] || location['venue_city']
    end

    city_counts[location['venue_city']] += venue['checkin_count']
  end

  city_counts.sort_by { |_, count| -count }.first(10).map do |city, count|
    { 'name' => city, 'checkin_count' => count }
  end
end
