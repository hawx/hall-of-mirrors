require 'fileutils'
require 'pathname'
require 'yaml'

# Constants to allow easier path resolution
HERE = Pathname.new(__FILE__) + '..' + '..'
ROOT = ENV['MIRROR_ROOT'] ? Pathname.new(ENV['MIRROR_ROOT']) : HERE

CONFIG_FILE = ROOT + 'config.yml'

FileUtils.mkdir_p ROOT

# Config is a globally available object to push configuration values onto. It
# uses the convention of namespaces to support multiple tools using the same
# config file.
#
# @example
#
#    Config.set :myapp, :auth, 'password'
#    # Saves the config file, so that later...
#
#    Config.get :myapp, :auth
#    #=> 'password'
#
Config = Class.new {
  def initialize
    @namespaces = {}

    if CONFIG_FILE.exist?
      @namespaces = YAML.load_file(ROOT + 'config.yml')
    end
  end

  def set(ns=nil, key, value)
    value.tap {
      @namespaces[ns] ||= {}
      @namespaces[ns][key] = value

      File.write CONFIG_FILE, YAML.dump(to_h)
    }
  end

  def get(ns, key=nil)
    return @namespaces[ns] unless key

    @namespaces[ns][key] if @namespaces.has_key?(ns)
  end

  def has?(ns, key=nil)
    return @namespaces.has_key?(ns) unless key

    @namespaces.has_key?(ns) && @namespaces[ns].has_key?(key)
  end

  def to_h
    @namespaces
  end
}.new
