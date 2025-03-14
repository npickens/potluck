# frozen_string_literal: true

require_relative('test_helper')

require('fileutils')
require('logger')
require('stringio')

class ServiceTest < Minitest::Test
  include(TestHelper)

  NULL_LOGGER = Logger.new('/dev/null').freeze
  MANAGE = {
    status: 'true',
    status_error_regex: /oops/,
    start: 'echo start',
    stop: 'echo stop',
  }.freeze

  ##########################################################################################################
  ## Hooks                                                                                                ##
  ##########################################################################################################

  def setup
    if Potluck::Service.class_variable_defined?(:@@launchctl)
      Potluck::Service.remove_class_variable(:@@launchctl)
    end

    FileUtils.rm_rf(TMP_DIR)
    FileUtils.mkdir_p(TMP_DIR)

    Potluck.config = Potluck::Config.new { |c| c.dir = TMP_DIR }
  end

  def teardown
    Potluck.config = Potluck::Config.new

    FileUtils.rm_rf(TMP_DIR)
  end

  ##########################################################################################################
  ## Constructor                                                                                          ##
  ##########################################################################################################

  test('enables management by default when launchctl is available') do
    Potluck::Service.stub(:launchctl?, true) do
      assert(Potluck::Service.new.manage?)
    end
  end

  test('disables management by default when launchctl is not available') do
    Potluck::Service.stub(:launchctl?, false) do
      refute(Potluck::Service.new.manage?)
    end
  end

  test('raises ServiceError if default management is enabled and launchctl is not available') do
    Potluck::Service.stub(:launchctl?, false) do
      error = assert_raises(Potluck::ServiceError) do
        Potluck::Service.new(manage: true)
      end

      assert_equal('Cannot manage Service: launchctl not found', error.message)
    end
  end

  test('accepts a configuration hash for non-launchctl management') do
    service = Potluck::Service.new(manage: MANAGE)

    assert(service.manage?)
    assert_equal(MANAGE[:status], service.send(:status_command))
    assert_equal(MANAGE[:status_error_regex], service.send(:status_error_regex))
    assert_equal(MANAGE[:start], service.send(:start_command))
    assert_equal(MANAGE[:stop], service.send(:stop_command))
  end

  ##########################################################################################################
  ## Management                                                                                           ##
  ##########################################################################################################

  test('#manage? returns true if default management is enabled') do
    Potluck::Service.stub(:launchctl?, true) do
      assert(Potluck::Service.new(manage: true).manage?)
    end
  end

  test('#manage? returns true if custom management is enabled') do
    assert(Potluck::Service.new(manage: MANAGE).manage?)
  end

  test('#manage? returns false if management is disabled') do
    refute(Potluck::Service.new(manage: false).manage?)
  end

  test('#manage_with_launchctl? returns true if default management is enabled') do
    Potluck::Service.stub(:launchctl?, true) do
      assert(Potluck::Service.new(manage: true).manage_with_launchctl?)
    end
  end

  test('#manage_with_launchctl? returns false if custom management is enabled') do
    refute(Potluck::Service.new(manage: MANAGE).manage_with_launchctl?)
  end

  test('#manage_with_launchctl? returns false if management is disabled') do
    refute(Potluck::Service.new(manage: false).manage_with_launchctl?)
  end

  ##########################################################################################################
  ## Status                                                                                               ##
  ##########################################################################################################

  test('#status returns :inactive if management is not enabled') do
    service = Potluck::Service.new(manage: false)

    assert_equal(:inactive, service.status)
  end

  test('#status returns :inactive if status command exits with non-zero status') do
    service = Potluck::Service.new(manage: MANAGE.merge({status: 'false'}))

    assert_equal(:inactive, service.status)
  end

  test('#status returns :error if status command output matches status command error regex') do
    service = Potluck::Service.new(manage: MANAGE.merge(status: 'echo "whoops"'))

    assert_equal(:error, service.status)
  end

  test('#status returns :active if status command succeeds and output does not match error regex') do
    service = Potluck::Service.new(manage: MANAGE.merge(status: 'echo "success"'))

    assert_equal(:active, service.status)
  end

  ##########################################################################################################
  ## Start                                                                                                ##
  ##########################################################################################################

  test('#start does nothing if management is not enabled') do
    service = Potluck::Service.new(manage: false)

    service.stub(:run, ->(cmd) { flunk("Expected: no command run\n  Actual: `#{cmd}` run") }) do
      service.start
    end
  end

  test('#start writes plist file to disk if launchctl management is enabled') do
    Potluck::Service.stub(:launchctl?, true) do
      service = Potluck::Service.new(logger: NULL_LOGGER, manage: true)
      stub_status(service, :inactive, :active)
      stub_run_noop(service)

      service.start
    end

    assert_path_exists(Potluck::Service.plist_path)
  end

  test('#start stops service before attempting to start if status is :error') do
    service = Potluck::Service.new(logger: NULL_LOGGER, manage: MANAGE)
    stub_status(service, :error, :active)

    stop_called = false
    service.stub(:stop, -> { stop_called = true }) do
      service.start
    end

    assert(stop_called, "Expected: #stop called\n  Actual: #stop not called")
  end

  test('#start does not start service if status is :active') do
    service = Potluck::Service.new(logger: NULL_LOGGER, manage: {})
    stub_status(service, :active)

    service.stub(:run, ->(cmd) { flunk("Expected: no command run\n  Actual: `#{cmd}` run") }) do
      service.start
    end
  end

  test('#start runs default start command when default management is enabled') do
    run_command = nil

    Potluck::Service.stub(:launchctl?, true) do
      service = Potluck::Service.new(logger: NULL_LOGGER, manage: true)
      stub_status(service, :inactive, :active)

      service.stub(:run, ->(cmd) { run_command = cmd }) do
        service.start
      end
    end

    assert_equal(
      "launchctl bootstrap gui/#{Process.uid} #{File.join(TMP_DIR, 'potluck.npickens.service.plist')}",
      run_command
    )
  end

  test('#start runs custom start command when custom management is enabled') do
    run_command = nil

    service = Potluck::Service.new(logger: NULL_LOGGER, manage: MANAGE)
    stub_status(service, :inactive, :active)

    service.stub(:run, ->(cmd) { run_command = cmd }) do
      service.start
    end

    assert_equal(MANAGE[:start], run_command)
  end

  test('#start waits until status is :active after running start command') do
    service = Potluck::Service.new(logger: NULL_LOGGER, manage: MANAGE)
    stub_status(service, :inactive, :inactive, :active)

    begin
      service.stub(:sleep, ->(time) { time }) do
        service.start
      end
    rescue => e
      flunk("Expected: no error\n  Actual: #{e.inspect}")
    end
  end

  test('#start raises ServiceError if status is not :active after running start command') do
    service = Potluck::Service.new(logger: NULL_LOGGER, manage: MANAGE)
    stub_status(service, :inactive, :error)

    error = assert_raises(Potluck::ServiceError) do
      service.start
    end

    assert_equal('Could not start Service', error.message)
  end

  test('#start logs statement that service was started') do
    io = StringIO.new
    service = Potluck::Service.new(logger: Logger.new(io), manage: MANAGE)
    stub_status(service, :inactive, :active)
    stub_wait_noop(service)

    service.start

    assert_match(/Service started$/, io.string)
  end

  ##########################################################################################################
  ## Stop                                                                                                 ##
  ##########################################################################################################

  test('#stop does nothing if management is not enabled') do
    service = Potluck::Service.new(manage: false)

    service.stub(:run, ->(cmd) { flunk("Expected: no command run\n  Actual: `#{cmd}` run") }) do
      service.stop
    end
  end

  test('#stop writes plist file to disk if launchctl management is enabled') do
    Potluck::Service.stub(:launchctl?, true) do
      service = Potluck::Service.new(logger: NULL_LOGGER, manage: true)
      stub_status(service, :active, :inactive)
      stub_run_noop(service)

      service.stop
    end

    assert_path_exists(Potluck::Service.plist_path)
  end

  test('#stop does not stop service if status is :inactive') do
    service = Potluck::Service.new(logger: NULL_LOGGER, manage: MANAGE)
    stub_status(service, :active)

    service.stub(:run, ->(cmd) { flunk("Expected: no command run\n  Actual: `#{cmd}` run") }) do
      service.start
    end
  end

  test('#stop runs default stop command when default management is enabled') do
    run_command = nil

    Potluck::Service.stub(:launchctl?, true) do
      service = Potluck::Service.new(logger: NULL_LOGGER, manage: true)
      stub_status(service, :active, :inactive)

      service.stub(:run, ->(cmd) { run_command = cmd }) do
        service.stop
      end
    end

    assert_equal("launchctl bootout gui/#{Process.uid}/potluck.npickens.service", run_command)
  end

  test('#stop runs custom stop command when custom management is enabled') do
    run_command = nil

    service = Potluck::Service.new(logger: NULL_LOGGER, manage: MANAGE)
    stub_status(service, :active, :inactive)

    service.stub(:run, ->(cmd) { run_command = cmd }) do
      service.stop
    end

    assert_equal(MANAGE[:stop], run_command)
  end

  test('#stop waits until status is :inactive after running stop command') do
    service = Potluck::Service.new(logger: NULL_LOGGER, manage: MANAGE)
    stub_status(service, :active, :active, :inactive)

    begin
      service.stub(:sleep, ->(time) { time }) do
        service.stop
      end
    rescue => e
      flunk("Expected: no error\n  Actual: #{e.inspect}")
    end
  end

  test('#stop raises ServiceError if status is not :inactive after running stop command') do
    service = Potluck::Service.new(logger: NULL_LOGGER, manage: MANAGE)
    stub_status(service, :active, :error)
    stub_wait_noop(service)

    error = assert_raises(Potluck::ServiceError) do
      service.stop
    end

    assert_equal('Could not stop Service', error.message)
  end

  test('#stop logs statement that service was stopped') do
    io = StringIO.new
    service = Potluck::Service.new(logger: Logger.new(io), manage: MANAGE)
    stub_status(service, :active, :inactive)

    service.stop

    assert_match(/Service stopped$/, io.string)
  end

  ##########################################################################################################
  ## Restart                                                                                              ##
  ##########################################################################################################

  test('#restart does nothing if management is not enabled') do
    service = Potluck::Service.new(manage: false)

    service.stub(:run, ->(cmd) { flunk("Expected: no command run\n  Actual: `#{cmd}` run") }) do
      service.restart
    end
  end

  test('#restart stops and starts the service if management is enabled') do
    service = Potluck::Service.new(manage: MANAGE)

    stop_called = false
    start_called = false

    service.stub(:stop, -> { stop_called = true }) do
      service.stub(:start, -> { start_called = true }) do
        service.restart
      end
    end

    assert(stop_called, "Expected: #stop called\n  Actual: #stop not called")
    assert(start_called, "Expected: #start called\n  Actual: #start not called")
  end

  ##########################################################################################################
  ## Run                                                                                                  ##
  ##########################################################################################################

  test('#run captures stderr output by default') do
    service = Potluck::Service.new(manage: MANAGE)
    output = service.run('hello() { echo Hello 1>&2; } && hello')

    assert_equal("Hello\n", output)
  end

  test('#run captures stderr output when capture_stderr: true') do
    service = Potluck::Service.new(manage: MANAGE)
    output = service.run('hello() { echo Hello 1>&2; } && hello 2>/dev/null', capture_stderr: true)

    assert_equal("Hello\n", output)
  end

  test('#run does not capture stderr output when capture_stderr: false') do
    service = Potluck::Service.new(manage: MANAGE)
    output = service.run('hello() { echo Hello 1>&2; } && hello 2>/dev/null', capture_stderr: false)

    assert_equal('', output)
  end

  test('#run logs output when command exit status is non-zero') do
    io = StringIO.new
    service = Potluck::Service.new(logger: Logger.new(io), manage: MANAGE)

    begin
      service.run('echo Hello && exit 1')
    rescue Potluck::ServiceError
      # Do nothing
    end

    assert_match(/ERROR .* Hello$/, io.string)
  end

  test('#run raises ServiceError when command exit status is non-zero') do
    service = Potluck::Service.new(manage: MANAGE)

    error = assert_raises(Potluck::ServiceError) do
      service.run('false')
    end

    assert_equal('Command exited with status 1: false', error.message)
  end

  ##########################################################################################################
  ## Logging                                                                                              ##
  ##########################################################################################################

  test('#log logs as info by default') do
    io = StringIO.new
    service = Potluck::Service.new(logger: Logger.new(io), manage: MANAGE)

    service.log('Hello')

    assert_match(/INFO .* Hello$/, io.string)
  end

  test('#log logs as info when error argument is false') do
    io = StringIO.new
    service = Potluck::Service.new(logger: Logger.new(io), manage: MANAGE)

    service.log('Hello', false)

    assert_match(/INFO .* Hello$/, io.string)
  end

  test('#log logs as error when error argument is truthy') do
    io = StringIO.new
    service = Potluck::Service.new(logger: Logger.new(io), manage: MANAGE)

    service.log('Hello', :error)

    assert_match(/ERROR .* Hello$/, io.string)
  end

  test('#log logs to stdout when no logger is supplied') do
    io = StringIO.new
    service = Potluck::Service.new(manage: MANAGE)

    $stdout = io
    service.log('Hello')

    assert_equal("Hello\n", io.string)
  ensure
    $stdout = STDOUT
  end

  test('#log logs to stderr when no logger is supplied and error argument is truthy') do
    io = StringIO.new
    service = Potluck::Service.new(manage: MANAGE)

    $stderr = io
    service.log('Hello', :error)

    assert_equal("Hello\n", io.string)
  ensure
    $stderr = STDERR
  end

  ##########################################################################################################
  ## Names                                                                                                ##
  ##########################################################################################################

  test('.pretty_name returns human-friendly name of the service') do
    assert_equal('Service', Potluck::Service.pretty_name)
  end

  test('.service_name returns computer-friendly name of the service') do
    assert_equal('service', Potluck::Service.service_name)
  end

  test('.launchctl_name returns launchctl name of the service') do
    assert_equal('potluck.npickens.service', Potluck::Service.launchctl_name)
  end

  test('.plist_path returns path of the plist file') do
    assert_equal(File.join(TMP_DIR, 'potluck.npickens.service.plist'), Potluck::Service.plist_path)
  end

  ##########################################################################################################
  ## Plist                                                                                                ##
  ##########################################################################################################

  test('.plist returns plist content') do
    plist = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      #{'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0' \
        '.dtd">'}
      <plist version="1.0">
      <dict>
        <key>Label</key>
        <string>potluck.npickens.service</string>
        <key>RunAtLoad</key>
        <true/>
        <key>KeepAlive</key>
        <false/>
        <other>
      </dict>
      </plist>
    XML

    assert_equal(plist, Potluck::Service.plist('<other>'))
  end

  test('.write_plist writes plist content to plist file') do
    Potluck::Service.write_plist

    assert_path_exists(Potluck::Service.plist_path)
    assert_equal(Potluck::Service.plist, File.read(Potluck::Service.plist_path))
  end

  ##########################################################################################################
  ## Launchctl                                                                                            ##
  ##########################################################################################################

  test('.luanchctl? returns true if launchctl is available') do
    Potluck::Service.stub(:`, ->(_) { Kernel.send(:`, 'true') }) do
      assert(Potluck::Service.launchctl?)
    end
  end

  test('.luanchctl? returns false if launchctl is not available') do
    Potluck::Service.stub(:`, ->(_) { Kernel.send(:`, 'false') }) do
      refute(Potluck::Service.launchctl?)
    end
  end

  test('.ensure_launchctl! does nothing if launchctl is available') do
    Potluck::Service.stub(:launchctl?, true) do
      Potluck::Service.ensure_launchctl!
    rescue => e
      flunk("Expected: no error\n  Actual: #{e.inspect}")
    end
  end

  test('.ensure_launchctl! raises ServiceError if launchctl is not available') do
    error = assert_raises(Potluck::ServiceError) do
      Potluck::Service.stub(:launchctl?, false) do
        Potluck::Service.ensure_launchctl!
      end
    end

    assert_equal('Cannot manage Service: launchctl not found', error.message)
  end

  ##########################################################################################################
  ## Helpers                                                                                              ##
  ##########################################################################################################

  def stub_status(service, *statuses)
    service.instance_variable_set(:@__statuses__, statuses)
    service.instance_variable_set(:@__status_calls__, -1)

    def service.status
      @__statuses__[[@__status_calls__ += 1, @__statuses__.size - 1].min]
    end
  end

  def stub_run_noop(service)
    def service.run(_) end
  end

  def stub_wait_noop(service)
    def service.wait(timeout = nil, &block) end
  end
end
