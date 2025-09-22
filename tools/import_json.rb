require 'json'
require 'sqlite3'

json_to_import = ARGV[0]
sqlite_output = ARGV[1]

unless json_to_import and sqlite_output
  puts "ruby import_json.rb <json> retappd.sqlite"
  exit 1
end

if File.exist?(sqlite_output)
  puts "#{sqlite_output} already exists. Quitting."
  exit
end

db = SQLite3::Database.new(sqlite_output)
db.results_as_hash = true
db.execute("
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
db.execute("
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
db.execute("
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
db.execute("
 CREATE TABLE IF NOT EXISTS venue (
 id INTEGER PRIMARY KEY,
 name TEXT,
 location_json TEXT,
 contact_json TEXT,
 icon_url TEXT
 );
")
db.execute("
 CREATE TABLE IF NOT EXISTS badge (
 id INTEGER PRIMARY KEY,
 name TEXT,
 description TEXT,
 created_at TIMESTAMP,
 checkin_id INTEGER,
 image_url TEXT
 );
")

JSON.parse(File.read(json_to_import)).each do |beer|
  brewery_json = {
    "brewery_city" => beer["brewery_city"],
    "brewery_state" => beer["brewery_state"]
  }
  db.execute(
    "INSERT OR IGNORE INTO brewery (
                id, name, page_url, country_name, location_json
               ) VALUES (?, ?, ?, ?, ?)",
    [beer['brewery_id'], beer['brewery_name'], beer['brewery_url'], beer['brewery_country'], brewery_json.to_json]
  )
  db.execute("INSERT OR IGNORE INTO beer (
                id, name, label_url, abv, ibu, style, description, rating_score
               ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", [beer['bid'], beer['beer_url'], beer['beer_abv'], beer['beer_ibu'], beer['beer_type'], beer['global_rating_score']])
  location_json = {
    "venue_address" => '',
    "venue_city" => beer['venue_city'],
    "venue_state" => beer['venue_state'],
    "venue_country" => beer['venie_country'],
    "lat" => beer['venue_lat'],
    "lng" => beer['venue_lng']
  }
  db.execute("INSERT OR IGNORE INTO venue (
                id, name, location_json
               ) VALUES (?, ?, ?)", [nil, beer['venue_name'], location_json.to_json])

  venue_id = db.execute('SELECT id from venue WHERE name=? AND location_json=?', [beer['venue_name'], location_json.to_json])[0]['id']

  db.execute(
    "INSERT OR IGNORE INTO checkin (
                id, created_at, rating_score, comment,  beer_id, venue_id
               ) VALUES (?, ?, ?, ?, ?, ?)",
    [beer['checkin_id'], beer['created_at'], beer['rating_score'], beer['comment'], beer['bid'], venue_id]
  )
end
