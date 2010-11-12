# Be sure to restart your web server when you modify this file.

# Uncomment below to force Rails into production mode when
# you don't control web/app server and can't set it the proper way
# ENV['RAILS_ENV'] ||= 'production'

RAILS_GEM_VERSION = '>=2.3.8' unless defined? RAILS_GEM_VERSION
# Bootstrap the Rails environment, frameworks, and default configuration
require File.join(File.dirname(__FILE__), 'boot')

require "common/libxmlactivexml"
require 'custom_logger'
require 'fileutils'

# create important directories that are needed at runtime
FileUtils.mkdir_p("#{RAILS_ROOT}/log")
FileUtils.mkdir_p("#{RAILS_ROOT}/tmp")
FileUtils.mkdir_p("#{RAILS_ROOT}/tmp/cache")
FileUtils.mkdir_p("#{RAILS_ROOT}/tmp/pids")
FileUtils.mkdir_p("#{RAILS_ROOT}/tmp/sessions")
FileUtils.mkdir_p("#{RAILS_ROOT}/tmp/sockets")

init = Rails::Initializer.run do |config|
  # Settings in config/environments/* take precedence those specified here

  # Skip frameworks you're not going to use
  config.frameworks -= [ :action_web_service, :active_resource ]

  # Add additional load paths for your own custom dirs
  # config.load_paths += %W( #{RAILS_ROOT}/extras )

  # Force all environments to use the same logger level
  # (by default production uses :info, the others :debug)
  # config.log_level = :debug

  # Use the database for sessions instead of the file system
  # (create the session table with 'rake create_sessions_table')
  config.action_controller.session_store = :active_record_store
  # default secret
  secret = "iofupo3i4u5097p09gfsnaf7g8974lh1j3khdlsufdzg9p889234"
  if File.exist? "#{RAILS_ROOT}/config/secret.key"
    file = File.open( "#{RAILS_ROOT}/config/secret.key", "r" )
    secret = file.readline
  end
  config.action_controller.session = {
    :prefix => "ruby_webclient_session",
    :key => "opensuse_webclient_session",
    :secret => secret
  }

  # Enable page/fragment caching by setting a file-based store
  # (remember to create the caching directory and make it readable to the application)
  # config.action_controller.fragment_cache_store = :file_store, "#{RAILS_ROOT}/cache"

  config.gem 'daemons'
  config.gem 'delayed_job'
  config.gem 'libxml-ruby'
  config.gem 'exception_notification', :version => '<= 1.1'

  # Activate observers that should always be running
  # config.active_record.observers = :cacher, :garbage_collector

  # Make Active Record use UTC-base instead of local time
  # config.active_record.default_timezone = :utc

  # Use Active Record's schema dumper instead of SQL when creating the test database
  # (enables use of different database adapters for development and test environments)
  # config.active_record.schema_format = :ruby

  config.cache_store = :compressed_mem_cache_store, 'localhost:11211', {:namespace => 'obs-webclient'}

  # See Rails::Configuration for more options

  config.logger = NiceLogger.new(config.log_path)

end

ActionController::Base.relative_url_root = CONFIG['relative_url_root'] if CONFIG['relative_url_root']

require 'ostruct'
require "cache_immutable_fix.rb"

# Exception notifier plugin configuration
ExceptionNotifier.sender_address = %("OBS Webclient" <admin@opensuse.org>)
ExceptionNotifier.email_prefix = "[OBS web error] "
ExceptionNotifier.exception_recipients = CONFIG['exception_recipients']

if CONFIG['visible_architectures']
   VISIBLE_ARCHITECTURES=CONFIG['visible_architectures']
else
   VISIBLE_ARCHITECTURES=[ :i586, :x86_64 ]
end
if CONFIG['default_enabled_architectures']
   DEFAULT_ENABLED_ARCHITECTURES=CONFIG['default_enabled_architectures']
else
   DEFAULT_ENABLED_ARCHITECTURES=[ :i586, :x86_64 ]
end
if CONFIG['hide_private_options'] == true
   HIDE_PRIVATE_OPTIONS = true
else
   HIDE_PRIVATE_OPTIONS = false
end

SOURCEREVISION = 'master'
begin
  SOURCEREVISION = File.open("#{RAILS_ROOT}/REVISION").read
rescue Errno::ENOENT
end

#DOWNLOAD_URL = "http://download.opensuse.org/repositories"
#BUGZILLA_HOST = nil

ActiveXML::Base.config do |conf|
  conf.setup_transport do |map|
    map.default_server :rest, "#{FRONTEND_HOST}:#{FRONTEND_PORT}"

    map.connect :project, "rest:///source/:name/_meta?:view",
      :all    => "rest:///source/",
      :delete => "rest:///source/:name?:force"
    map.connect :package, "rest:///source/:project/:name/_meta?:view",
      :all    => "rest:///source/:project"

    map.connect :tagcloud, "rest:///tag/tagcloud?limit=:limit",
      :alltags  => "rest:///tag/tagcloud?limit=:limit",
      :mytags => "rest:///user/:user/tags/_tagcloud?limit=:limit",
      :hierarchical_browsing => "rest:///tag/tagcloud?limit=:limit"

    map.connect :tag, "rest:///user/:user/tags/:project/:package",
      :tags_by_object => "rest:///source/:project/:package/_tags"

    map.connect :person, "rest:///person/:login"
    map.connect :unregisteredperson, "rest:///person/register"
    map.connect :userchangepasswd, "rest:///person/changepasswd"

    map.connect :architecture, "rest:///architecture"

    map.connect :wizard, "rest:///source/:project/:package/_wizard?:response"

    map.connect :directory, "rest:///source/:project/:package?:expand&:rev"
    map.connect :link, "rest:///source/:project/:package/_link"
    map.connect :service, "rest:///source/:project/:package/_service"
    map.connect :file, "rest:///source/:project/:package/:filename?:expand&:rev"
    map.connect :jobhislist, "rest:///build/:project/:repository/:arch/_jobhistory?:limit&:code"

    map.connect :buildresult, "rest:///build/:project/_result?:view&:package&:code&:lastbuild&:arch&:repository"
    map.connect :fileinfo, "rest:///build/:project/:repository/:arch/:package/:filename?:view"

    map.connect :result, "rest:///result/:project/:platform/:package/:arch/result"
    map.connect :packstatus, "rest:///result/:project/packstatus?:command"

    map.connect :collection, "rest:///search/:what?match=:predicate",
      :id => "rest:///search/:what/id?match=:predicate",
      :tag => "rest:///tag/:tagname/:type",
      :tags_by_user => "rest:///user/:user/tags/:type",
      :hierarchical_browsing => "rest:///tag/browsing/_hierarchical?tags=:tags"

    map.connect :bsrequest, "rest:///request/:id", :create => "rest:///request?cmd=create"

    map.connect :packageattribute, "rest:///search/attribute?:namespace&:name&:project"
 
    map.connect :attribute, "rest:///source/:project/:package/_attribute/:attribute",
      :project => "rest:///source/:project/_attribute/:attribute",
      :namespaces => "rest:///attribute",
      :namespace_config => "rest:///attribute/:namespace/_meta",
      :config => "rest:///attribute/:namespace/:attribute/_meta",
      :attributes => "rest:///attribute/:namespace"   

    map.connect :patchinfo, "rest:///source/:project/:package/_patchinfo"
 
    # Monitor
    map.connect :workerstatus, 'rest:///status/workerstatus',
      :all => 'rest:///status/workerstatus'

    # Statistics
    map.connect :latestadded, 'rest:///statistics/latest_added?:limit',
      :specific => 'rest:///statistics/added_timestamp/:project/:package'
    map.connect :latestupdated, 'rest:///statistics/latest_updated?:limit',
      :specific => 'rest:///statistics/updated_timestamp/:project/:package'
    map.connect :downloadcounter, 'rest:///statistics/download_counter' +
      '?:project&:package&:arch&:repo&:group_by&:limit'
    map.connect :rating, 'rest:///statistics/rating/:project/:package',
      :all => 'rest:///statistics/highest_rated?:limit'
    map.connect :mostactive, 'rest:///statistics/most_active?:type&:limit',
      :specific => 'rest:///statistics/activity/:project/:package'
    map.connect :globalcounters, 'rest:///statistics/global_counters',
      :all => 'rest:///statistics/global_counters'

    # Status Messages
    map.connect :statusmessage, 'rest:///status/messages/:id/?:limit'

    map.connect :distribution, "rest:///public/distributions",
      :all    => "rest:///public/distributions"

    map.connect :projectstatus, 'rest:///status/project/:project'

    map.connect :builddepinfo, 'rest:///build/:project/:repository/:arch/_builddepinfo?:package&:limit&:code'

  end
  ActiveXML::Config.transport_for( :project ).set_additional_header( "User-Agent", "obs-webui/#{CONFIG['version']}" )


end

