#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'lastfm'
require 'clive/output'
require 'fileutils'
require 'pathname'
require 'seq/paged'
require 'digest/md5'
require 'pp'
require 'time'

require 'dm-core'
require 'dm-migrations'
require 'dm-sqlite-adapter'

HERE = Pathname.new(__FILE__) + '..'


require_relative 'app/models'

db_path = (HERE.realpath + 'hawx_' + 'plays.db').to_s
# DataMapper::Logger.new($stdout, :debug)
DataMapper.setup(:default, "sqlite://#{db_path}")

# Notes:
#  - Not every artist and album has an :mbid, hence the :id field
#  - ...

DataMapper.finalize
# DataMapper.auto_upgrade!

class User
  attr_reader :name

  def initialize(api, name)
    @api  = api
    @name = name
  end

  def save_plays
    newest = Play.first(:order => :date).date.to_time
    oldest = Play.last(:order => :date).date.to_time

    pager = Seq::Paged.new do |page|
      puts "Getting page #{page}"
      sleep(10)
      opts = {
        user:  @name,
        page:  page,
        limit: 200    # max page size allowed
      }

      @api.user.get_recent_tracks(opts)
    end

    pager.instance_variable_set(:@page, START_PAGE) if defined?(START_PAGE)

    # Will take a while!
    pager.each do |track|
      next if track['nowplaying'] == 'true'

      time = Time.at(track['date']['uts'].to_i)
      if time.between?(newest, oldest)
        print "  skipping ".red + "#{track['name']} (#{time.to_s})\n".grey
        next
      end

      artist = Artist.first_or_create(mbid: track['artist']['mbid'],
                                      name: track['artist']['content'])

      album = Album.first_or_create(mbid: track['album']['mbid'],
                                    name: track['album']['content'])

      Play.first_or_create(name:   track['name'],
                           mbid:   track['mbid'],
                           url:    track['url'],
                           date:   time,
                           artist: artist,
                           album:  album)

      # Need to re-adjust oldest and newest!
      print "  added ".grey + "#{track['name']} (#{time.to_s})\n"
    end
  end

  def data
    @data ||= @api.user.get_info(user: @name)
  end

  def to_json
    JSON.pretty_generate data
  end

  def path
    HERE + @name
  end

  def write
    wrote = false
    print path.to_s.blue.bold
    FileUtils.mkdir_p path

    unless (path + 'data.json').exist?
      File.write(path + 'data.json', to_json)
      print "\n  wrote ".grey + "data.json"
      wrote = true
    end

    if wrote
      print "\n\n"
    else
      print "\r  skipped ".red + path.to_s.grey + "\n"
    end
  end
end


lastfm = Lastfm.new(ENV['LASTFM_KEY'], ENV['LASTFM_SECRET'])
lastfm.session = File.read(HERE + '_auth')

user = User.new(lastfm, 'hawx_')
# user.write

user.save_plays
