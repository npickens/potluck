# Potluck

Potluck is an extensible Ruby framework for configuring, controlling, and interacting with external
processes. It leverages `launchctl` for starting and stopping processes when the command is available (e.g.
when developing locally on macOS) while gracefully taking either a more passive or manual role with external
processes in other environments (e.g. production).

The core Potluck gem provides a simple interface which is used by service-specific extensions to the gem.
Currently there are two official extensions:

* [Potluck::Nginx](potluck-nginx/README.md) - Generates Nginx configuration files and (optionally) controls
  the Nginx process with `launchctl` or manual commands. Allows for multiple Ruby apps as well as other
  external processes to all seamlessly use Nginx simultaneously.
* [Potluck::Postgres](potluck-postgres/README.md) - Provides control of the Postgres process and basic
  common functionality for connecting to and setting up a database. Uses the
  [Sequel](https://github.com/jeremyevans/sequel) and [pg](https://github.com/ged/ruby-pg) gems.

## Installation

Add this line to your Gemfile:

```ruby
gem('potluck')
```

Or install manually on the command line:

```bash
gem install potluck
```

## Usage

The core Potluck gem is not meant to be used directly. Rather its `Service` class defines a common interface
for external processes which can be inherited by service-specific child classes. See
[Potluck::Nginx](potluck-nginx/README.md) and [Potluck::Postgres](potluck-postgres/README.md) for examples.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/npickens/potluck.

## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
