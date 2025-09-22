# Retappd 

## About

This is a simple Dashboard to display stats about my beer-based alcoholism.

## 🚨⚠️🚨WARNING 🚨⚠️🚨 This was at least 70% VibeCoded.


I do not know a thing about HTML/CSS or Javascript and let the AI do its thing. If it's gross, don't blame me.

## Installing

### If you have already a working sqlite file with all your data pulled out of somewhere


```
$ git clone https://github.com/conchyliculture/retappd
$ cd retappd
$ cp config.env .env
$ vim .env
RETAPPD_USERNAME="username"
RETAPPD_ALLOWED_HOSTS="retappd.domain.com,10.0.5.2"
```

### If you want to use the script to pull data regularly

```
docker exec retappd ruby retappd_dump.rb --update 2>&1 > /dev/null
docker compose down
docker compose up -d
```

But you also need to pass the proper env variables

```
$ vim .env
RETAPPD_ALLOWED_HOSTS="retappd.domain.com,10.0.5.2"
RETAPPD_USERNAME="username"
RETAPPD_PASSWORD="password"
RETAPPD_CLIENT_ID="1234567890123456789012345678901234567890"
RETAPPD_CLIENT_SECRET="1234567890123456789012345678901234567890"
RETAPPD_DEVICE_ID="1234561234567890"
```

Only the USERNAME above is required to display the dashboard. The rest is used to run the update script that pulls your data.

You'll have to figure out yourself how to get some working values for the  other variables there...
