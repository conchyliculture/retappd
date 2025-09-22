# Retappd 

## About

This is a simple Dashboard to display stats about my beer-based alcoholism.

## 🚨⚠️🚨WARNING 🚨⚠️🚨 This was at least 70% VibeCoded.

I do not know a thing about HTML/CSS or Javascript and let the AI do its thing. If it's gross, don't blame me.

## Installing

### If you have already a working sqlite file with all your data exported

```
$ git clone https://github.com/conchyliculture/retappd
$ cd retappd
$ cp config.env .env
$ vim .env
RETAPPD_USERNAME="username"
RETAPPD_ALLOWED_HOSTS="retappd.domain.com,10.0.5.2"
```

### If you want to use the script to pull data regularly

Have a script, like `reload.sh` with the following:
```
docker exec retappd ruby retappd_dump.rb --update 2>&1 > /dev/null
docker compose down
docker compose up -d
```

and then a cron that runs the script once a day.


You also need to pass the proper env variables

```
$ vim .env
RETAPPD_ALLOWED_HOSTS="retappd.domain.com,10.0.5.2"
RETAPPD_USERNAME="username"
RETAPPD_PASSWORD="password"
RETAPPD_CLIENT_ID="1234567890123456789012345678901234567890"
RETAPPD_CLIENT_SECRET="1234567890123456789012345678901234567890"
```

Only the USERNAME above is required to display the dashboard. The rest is used to run the update script that pulls your data.

Please see [The doc](https://untappd.com/api/docs) to get them.

## Getting the data

YOU WILL NEED TO BE AN UNTAPPD INSIDER 💸💸💸.

#### Use the script to export data using the API

```
$ cp config.env .env
```

And edit it appropriately. Please see [The doc](https://untappd.com/api/docs) to get the credentials.

#### Do an export

You can export some of the data using Untappd' premium (and expensive) feature (https://untappd.com/user/xxxx/beers) as JSON,
and then run the import script.

`mkdir -p data ; ruby tools/import_json.sqlite /tmp/export.json data/retappd.sqlite`

You will miss some of the information that the Dashboard uses, though (such as Breweries locations).
