# Potluck Changelog

## Upcoming (Unreleased)

* Nothing yet

## 0.0.8 (2025 March 19)

* **Use a DSL rather than a direct hash for Nginx configuration**
* Ensure raw Nginx config blocks get concatenated rather than overwritten
* Use 'http2 on' instead of deprecated 'listen ... http2' in Nginx config
* Normalize URLs using Nginx maps instead of if statements
* Raise Sequel's errors instead of wrapping them in `Postgres#connect`
* Use correct port when performing Nginx URL normalization redirect
* **Add Config class to allow for custom directory and Homebrew locations**
* **Require Ruby 3.0.0 or later**
* **Deprecate `Postgres#migrate`**

## 0.0.7 (2023 March 7)

* **Update service plists to work with Homebrew installed on Apple silicon**
* **Update Postgres plist per Homebrew's versioned install scheme**
* Fix off-by-one error when getting index of last Sequel migration

## 0.0.6 (2022 January 20)

* **Grant permissions when Postgres role is automatically created**
* **Rename `Service#run` `redirect_stderr:` parameter to `capture_stderr:`**
* Write plist file before stopping as well as before starting a service
* Don't force Service child classes to provide plist content
* Fix call to get service name when raising error about launchctl missing

## 0.0.5 (2021 December 31)

* Deep merge Nginx SSL config hashes
* **Raise instead of aborting on errors with Postgres setup**
* Disconnect before stopping Postgres
* Add and use ServiceError class for service errors
* Only suppress Postgres migration table query logs if log level is info
* **Remove deprecated Dish class**
* **Remove deprecated is_local setting from Service class**

## 0.0.4 (2021 December 28)

* Ensure Potluck directory exists before attempting to write plist file
* **Rename Dish class to Service**
* More accurately set Host and X-Forwarded-Port headers in Nginx
* Set headers on error pages in Nginx
* Add application/xml and text/javascript to Nginx gzip types

## 0.0.3 (2021 December 15)

* **Add non-launchctl control for Nginx**
* **Allow custom commands for managing services**
* Only ensure host entries on Nginx start if option is specified

## 0.0.2 (2021 December 13)

* **Add Postgres gem extension**
* **Add Nginx gem extension**

## 0.0.1 (2021 March 27)

* Release initial gem
