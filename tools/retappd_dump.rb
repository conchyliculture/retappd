require "optparse"
require "time"
require "digest"
require "fileutils"
require 'json'
require "httpx"
require "sqlite3"

class Badge
  attr_accessor :id, :name, :description, :image_url, :created_at

  def load_from_json(json)
    @id = json['badge_id']
    @name = json['badge_name']
    @description = json['badge_description']
    @created_at = Time.parse(json['created_at'])
    @image_url = json['badge_image']['lg']
    return self
  end
end

class Beer
  attr_accessor :id, :name, :label_url, :abv, :ibu, :style, :description, :rating_score, :rating_count, :brewery, :slug

  def load_from_json(json)
    if json['beer']
      json = json['beer']
    end
    if json['brewery']
      @brewery = Brewery.new.load_from_json(json['brewery'])
    end
    @id = json['bid']
    @name = json['beer_name']
    @label_url = json['beer_label']
    @abv = json['beer_abv']
    @ibu = json['beer_ibu']
    @style = json['beer_style']
    @description = json['beer_description']
    @rating_score = json['rating_score']
    @rating_count = json['rating_count']
    @slug = json['beer_slug']
    return self
  end
end

class Brewery
  attr_accessor :id, :name, :page_url, :type, :label_url, :country_name, :contact_json, :location_json, :slug

  def load_from_json(json)
    if json['brewery']
      json = json['brewery']
    end
    @id = json['brewery_id']
    @name = json['brewery_name']
    @page_url = "https://untappd.com#{json['brewery_page_url']}"
    @type = json['brewery_type']
    @country_name = json['country_name']
    @contact_json = json['contact']
    @location_json = json['location']
    @slug = json['brewery_slug']
    return self
  end

  def to_s
    return @name
  end
end

class Venue
  attr_accessor :id, :name, :location, :icon_url, :contact

  def load_from_json(json)
    if json['venue']
      json = json['venue']
    end
    @id = json['venue_id']
    @name = json['venue_name']
    @location = json['location'].to_json
    @contact = json['contact'].to_json
    @icon_url = json['venue_icon']['lg']
    return self
  end
end

class Checkin
  attr_accessor :id, :created_at, :rating_score, :comment, :user_id, :venue, :beer, :json, :badges

  def load_from_json(json)
    if json['beer']
      @beer = Beer.new.load_from_json(json['beer'])
    end
    if json['brewery']
      @beer.brewery = Brewery.new.load_from_json(json['brewery'])
    end
    if json['badges']
      @badges = json['badges']['items'].map { |b| Badge.new.load_from_json(b) }
    end
    unless json['venue'].empty?
      @venue = Venue.new.load_from_json(json['venue'])
    end
    @id = json['checkin_id']
    @created_at = Time.parse(json['created_at'])
    @comment = json['checkin_comment']
    @rating_score = json['rating_score']
    @user_id = json['user']['uid']
    return self
  end
end

class RetappdDB
  def initialize(dbfile)
    @db = SQLite3::Database.new(dbfile)
    @db.results_as_hash = true
    @db.execute("
    CREATE TABLE IF NOT EXISTS beer (
     id INTEGER PRIMARY KEY,
     brewery_id INTEGER,
     name TEXT,
     label_url TEXT,
     abv INTEGER,
     ibu INTEGER,
     style TEXT,
     description TEXT,
     rating_score FLOAT,
     rating_count INTEGER,
     slug TEXT
    );")
    @db.execute("
     CREATE TABLE IF NOT EXISTS brewery (
     id INTEGER PRIMARY KEY,
     name TEXT,
     page_url TEXT,
     type TEXT,
     country_name TEXT,
     contact_json TEXT,
     location_json TEXT,
     slug TEXT
     );
    ")
    @db.execute("
     CREATE TABLE IF NOT EXISTS checkin (
     id INTEGER PRIMARY KEY,
     created_at TIMESTAMP,
     rating_score FLOAT,
     comment TEXT,
     beer_id INTEGER,
     user_id INTEGER,
     venue_id INTEGER
     );
    ")
    @db.execute("
     CREATE TABLE IF NOT EXISTS venue (
     id INTEGER PRIMARY KEY,
     name TEXT,
     location_json TEXT,
     contact_json TEXT,
     icon_url TEXT
     );
    ")
    @db.execute("
     CREATE TABLE IF NOT EXISTS badge (
     id INTEGER PRIMARY KEY,
     name TEXT,
     description TEXT,
     created_at TIMESTAMP,
     checkin_id INTEGER,
     image_url TEXT
     );
    ")
  end

  def add_beer(beer)
    @db.execute("INSERT OR IGNORE INTO beer (
                id, name, label_url, abv, ibu, style, description, rating_score, rating_count, slug
               ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", [beer.id, beer.name, beer.label_url, beer.abv, beer.ibu, beer.style, beer.description, beer.rating_score, beer.rating_count, beer.slug])
    if beer.brewery
      add_brewery(beer.brewery)
      @db.execute("UPDATE beer set brewery_id =? WHERE id = ?", [beer.brewery.id, beer.id])
    end
  end

  def add_brewery(brewery)
    @db.execute("INSERT OR IGNORE INTO brewery (
                id, name, page_url, type, country_name, contact_json, location_json, slug
               ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                [brewery.id, brewery.name, brewery.page_url, brewery.type, brewery.country_name, brewery.contact_json.to_json, brewery.location_json.to_json, brewery.slug])
  end

  def add_checkin(checkin)
    @db.execute("INSERT OR IGNORE INTO checkin (
                id, created_at, rating_score, comment, user_id, beer_id
               ) VALUES (?, ?, ?, ?, ?, ?)",
                [checkin.id, checkin.created_at.strftime('%Y-%m-%d %H:%M:%S %:z'), checkin.rating_score, checkin.comment, checkin.user_id, checkin.beer.id])
    if checkin.venue
      add_venue(checkin.venue)
      @db.execute("UPDATE checkin SET venue_id = ? WHERE id = ?", [checkin.venue.id, checkin.id])
    end
    if checkin.beer
      add_beer(checkin.beer)
      @db.execute("UPDATE checkin SET beer_id = ? WHERE id = ?", [checkin.beer.id, checkin.id])
    end
    checkin.badges.each do |badge|
      add_badge(badge, checkin.id)
    end
  end

  def add_venue(venue)
    @db.execute("INSERT OR IGNORE INTO venue (
                id, name, location_json, icon_url, contact_json
               ) VALUES (?, ?, ?, ?, ?)", [venue.id, venue.name, venue.location, venue.icon_url, venue.contact])
  end

  def add_badge(badge, checkin_id)
    @db.execute("INSERT OR IGNORE INTO badge (
                id, name, description, created_at, checkin_id, image_url
               ) VALUES (?, ?, ?, ?, ?, ?)",
                [badge.id, badge.name, badge.description, badge.created_at.strftime('%Y-%m-%d %H:%M:%S %:z'), checkin_id, badge.image_url])
  end

  def execute(query)
    @db.execute(query)
  end
end

class Retappd
  API_V4_BASE_URL = "https://api.untappd.com/v4/".freeze # Need / at the end

  CACHE = "/tmp/retappd_cache".freeze

  def initialize(db_file, client_id, client_secret, device_id)
    @cache_dir = FileUtils.mkdir_p(CACHE)
    @device_id = device_id
    @client_id = client_id
    @client_secret = client_secret
    @username = nil
    @token = nil

    @base_query = "client_id=#{@client_id}&client_secret=#{@client_secret}&utv=4.0.0"

    @db = RetappdDB.new(db_file)

    @headers = {
      "accept-language" => "en",
      "accept-encoding" => "gzip",
      "content-type" => "application/x-www-form-urlencoded",
      "accept" => "application/json; charset=utf-8",
      "user-agent" => "okhttp/4.9.3"
    }
    if @device_id
      @headers["x-untappd-app-version"] = "4.5.10"
      @headers["x-untappd-app"] = "android"
      @headers["x-react-native"] = "1"
    end
  end

  def load_creds()
    if File.exist?('.creds')
      creds = JSON.parse(File.read('.creds').strip)[@username]
      unless creds
        puts "Can't find creds for user #{@username}"
        return
      end
      @token = creds['token']
      @user_info = creds['user_info']
      @date_joined = Time.parse(@user_info["date_joined"])
      @headers["authorization"] = "Bearer #{@token}"
    end
  end

  def cached_api(path, post_data: nil, params: nil, headers: nil, delay: 0)
    url = API_V4_BASE_URL
    url += (path.start_with?('/') ? path : "/#{path}")

    url = "#{url}?#{@base_query}"
    if params
      if params.is_a?(Hash)
        params = URI.encode_www_form(params)
      end
      url = "#{url}&#{params}"
    end

    headers ||= @headers
    cache_path = File.join(@cache_dir, Digest::MD5.hexdigest("#{url}_#{headers}"))
    if File.exist?(cache_path)
      puts "cache hit"
      return JSON.parse(JSON.parse(File.read(cache_path))['result'])['response']
    end

    if post_data
      res = HTTPX.post(url, headers: headers, body: post_data)
      File.new(cache_path, 'w+').write(JSON.pretty_generate(
                                         { 'url' => url, 'post_data' => post_data, 'timestamp' => Time.now, 'headers' => headers, 'result' => res.body }
                                       ))
    else
      res = HTTPX.get(url, headers: headers)
      File.new(cache_path, 'w+').write(JSON.pretty_generate(
                                         { 'url' => url, 'timestamp' => Time.now, 'headers' => headers, 'result' => res.body }
                                       ))
    end
    if delay
      sleep delay
    end

    return JSON.parse(res.body)['response']
  end

  def login(username, password)
    @username = username
    load_creds()

    if @token and username == @username
      puts "We already have a token for user #{@username}"
      return
    end
    data = "user_data=#{username}"

    j = cached_api("/xauth/validate_username", post_data: data)
    begin
      uid = j['uid']
    rescue StandardError
      puts "Error in response from validate_username"
      pp j
      raise
    end

    raise StandardError, "Error validating username, got #{j}" unless uid.to_s =~ /^[0-9]+$/

    data = "user_name=#{username}&user_password=#{password}&multi_account=true"
    if @device_id
      data = "#{data}&device_udid=#{@device_id}&device_name=Pixel%205&device_version=15&device_platform=Android&app_version=4.5.10"
    end

    j = cached_api("/xauth", post_data: data)
    @token = j["access_token"]
    raise StandardError, "Error validating username, got #{j}" unless @token =~ /^[0-9A-F]{40}+$/

    @headers["authorization"] = "Bearer #{@token}"
    j = cached_api("/helpers/appInit")

    @user_info = j["settings"]["user"]
    @date_joined = Time.parse(@user_info["date_joined"])
    raise StandardError, "Weird uid found in response (expected #{uid}): #{j} " unless @user_info["uid"].to_s == uid

    c = File.new('.creds', 'w')
    c.write(JSON.dump({
                        @username => {
                          'token' => @token,
                          'user_info' => @user_info
                        }
                      }))
    c.close
  end

  def get_user_infos(username)
    infos = JSON.parse(cached_api(
                         "/user/info/#{username}",
                         params: "compact=enhanced&badges=true&badgeLimit=5&rating_breakdown=light&beers=true"
                       ))
    puts "User infos for #{@username}: "
    puts infos["stats"]
  end

  def get_all_beers(username, start_date: nil)
    offset = 0
    loaded_beers = 0
    total = -1
    start_date = ((start_date || @date_joined) - 86_400).strftime('%Y-%m-%d')
    puts "Getting all checkins for #{username} since #{start_date}"

    loop do
      j = cached_api("/user/beers/#{username}", params: "offset=#{offset}&q=&sort=highest_rated_you&rating_score=&brewery_id=&type_id=&container_id=&country_id=&region_id=&start_date=#{start_date}&end_date=#{Time.now.strftime('%Y-%m-%d')}&timezoneOffset=2", delay: 1)

      unless j['pagination']['next_url'].empty?
        next_url = URI.parse(j['pagination']['next_url'])
        offset = next_url.query.split('&').select { |x| x.start_with?('offset=') }[0].split("=")[1]
      end
      puts "at offset #{offset}"
      total = j['total_count'] if total == -1
      j['beers']['items'].each do |beer|
        beer = Beer.new.load_from_json(beer)
        @db.add_beer(beer)
        get_beer_checkins(beer.id)
        loaded_beers += 1
        if loaded_beers % 20 == 1
          puts "Loaded #{loaded_beers}"
        end
      end
      break if j['pagination']['next_url'] == ""
    end
    puts "Added #{loaded_beers} when total was #{total}"
  end

  def get_beer_from_api(bid)
    j = cached_api("/beer/info/#{bid}")
    Beer.new.load_from_json(j)
  end

  def get_beer_checkins(bid)
    offset = 0
    added_checkin = 0
    total = 0
    loop do
      j = cached_api("/beer/checkins/#{bid}", params: "type=filter&offset=#{offset}")

      unless j['pagination']['next_url'].empty?
        next_url = URI.parse(j['pagination']['next_url'])
        offset = next_url.query.split('&').select { |x| x.start_with?('offset=') }[0].split("=")[1]
      end
      total = j['checkins']['count']
      j['checkins']['items'].each do |checkin|
        next unless checkin['user']['user_name'] == @username

        checkin = Checkin.new.load_from_json(checkin)
        @db.add_checkin(checkin)
        added_checkin += 1
      end
      break if j['pagination']['next_url'] == ""
    end
    puts "Added #{added_checkin} when total was #{total}"
    raise StandardError, "Error they don't match" unless added_checkin == total
  end

  def search_beer(query)
    j = cached_api('/search/beer', params: "q=#{query}")
  end

  def get_last_checkin_from_db()
    Time.parse(@db.execute("SELECT MAX(created_at) as last from checkin ")[0]['last'])
  end
end

# 1432402 : the crafty brewing company, 3 checkins, 2 badges

options = {
  update: false,
  username: ENV['RETAPPD_USERNAME'],
  database: ENV['RETAPPD_DATABASE'] || 'data/retappd.sqlite',
  password: ENV['RETAPPD_PASSWORD']
}

OptionParser.new do |parser|
  parser.banner = "Usage: #{__FILE__} [options]"
  parser.on('--database=SQLITE_FILE', "Path to db file") do |x|
    options[:database] = x
  end
  parser.on('--update', "Update db from latest known checkin") do |_|
    options[:update] = true
  end
  parser.on('--username=USER', "username") do |x|
    options[:username] = x
  end
  parser.on('--password=PASSWORD', "password") do |x|
    options[:password] = x
  end
end.parse!

unless options[:database]
  puts "Need a path to a sqlite db file"
  exit 1
end

if options[:update]
  unless File.exist?(options[:database])
    puts "Called with --update but #{options[:database]} doesn't exist"
    exit
  end
  u = Retappd.new(options[:database], ENV['RETAPPD_CLIENT_ID'], ENV['RETAPPD_CLIENT_SECRET'], ENV['RETAPPD_DEVICE_ID'] || nil)
  u.login(options[:username], options[:password])
  last = u.get_last_checkin_from_db()
  u.get_all_beers(options[:username], start_date: last)
else
  puts "doing nothing lol"
end
#b = u.get_beer_from_api(3_113_282)
#u.get_user_infos()
