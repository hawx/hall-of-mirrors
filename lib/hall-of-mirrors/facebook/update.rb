#!/usr/bin/env ruby

gem 'json', '~> 1.7.7'

require 'set'
require 'mini_exiftool'
require 'fileutils'
require 'pathname'
require 'koala'
require 'json'
require 'pp'
require 'open-uri'
require 'clive'

module Hall::Facebook::Update
  class Photo
    include Writer

    attr_reader :data

    def initialize(album, data)
      @album = album
      @data = data
    end

    def id
      @data["id"]
    end

    def source
      @data["source"]
    end

    def thumb
      @data["images"].map {|hsh| hsh["source"] }.find {|s| s[-5..-1] == "a.jpg" }
    end

    def size
      [@data["height"], @data["width"]]
    end

    def created
      @data["created_time"]
    end

    def path
      @album.path + id.to_s
    end

    def self.thumb
      Proc.new do |obj, wr|
        name = 'thumb.jpg'
        open obj.thumb do |f|
          File.write(obj.path + name, f.read)
        end
        name
      end
    end

    def self.photo
      Proc.new do |obj, wr|
        name = 'photo.jpg'
        open obj.source do |f|
          File.write(obj.path + name, f.read)
        end

        photo = MiniExiftool.new (obj.path + name).to_s
        photo['DateTimeOriginal'] = obj.created.split("T").join(" ")
        photo.save
        name
      end
    end

    writeable :data, 'data.json', :data
    writeable :thumb, 'thumb.jpg', thumb
    writeable :photo, 'photo.jpg', photo
  end

  class Album
    include Writer

    def self.for(id)
      GRAPH.get_object("#{id}/albums").map {|a| Album.new(a) }
    end

    def self.with_id(id)
      Album.new GRAPH.get_object(id)
    end

    attr_reader :data

    def initialize(data)
      @data = data
    end

    def from
      @data['from']['id']
    end

    def user
      User.find from
    end

    def id
      @data["id"]
    end

    def size
      @data["count"]
    end

    def name
      @data["name"]
    end

    def path
      user.path + "photos" + id
    end

    # Filter out photos taken in Clubs, etc. because I don't really want 1000s of
    # photos of random people.
    def ignore?
      cat = @data['from']['category']

      cat == "Club" || cat == "Arts/entertainment/nightlife"
    end

    def photos
      return [] if ignore?

      photos = GRAPH.get_object(id + "?fields=photos.limit(200)")
      return [] unless photos['photos']

      PhotoIterator.new(GRAPH, self, photos)
    end

    writeable :album, 'data.json', :data do |obj|
      !obj.ignore?
    end

    def inspect
      "#<Album #{name}>"
    end
  end


  class PhotoIterator
    include Enumerable

    def initialize(graph, album, raw)
      @album = album
      @pager = Koala::Facebook::API::GraphCollection.new(raw['photos'], graph)
    end

    def each
      @pager.raw_response['data'].each do |data|
        yield Photo.new(@album, data)
      end

      while @pager.next_page_params
        @pager = @pager.next_page

        @pager.raw_response['data'].each do |data|
          yield Photo.new(@album, data)
        end
      end
    end
  end

  class User
    include Writer

    @@users = Set.new

    def self.find(id)
      @@users.find {|user| user.id.to_s == id.to_s } ||
        User.new(id).tap {|user| @@users << user }
    end

    def self.me
      @@me ||= User.new(GRAPH.get_object('me')['id']).tap {|user| @@users << user }
    end

    attr_reader :id

    def initialize(id)
      @id = id
    end

    def path
      ROOT + 'facebook' + id.to_s
    end

    def albums
      @albums ||= Album.for(@id)
    end

    def connected_people
      return @connected_people if @connected_people

      people = Set.new

      albums.each do |album|
        if album.data['comments']
          people += album.data['comments']['data'].map {|data|
            data['from']['id']
          }
        end

        if album.data['likes']
          people += album.data['likes']['data'].map {|data|
            data['id']
          }
        end
      end

      @connected_people = people.delete(@id).map {|id| User.new(id) }
    end

    def connected_albums
      return @connected_albums if @connected_albums

      albums = Set.new

      photos_of.each_slice(50) do |photos|
        albums += GRAPH.batch do |batch_api|
          photos.each do |photo|
            batch_api.get_object(photo.id + '?fields=album') {|r|
              r['album']['id'] if r['album']
            }
          end
        end
      end

      @connected_albums = albums.reject(&:nil?).map {|id| Album.with_id(id) }
    end

    def photos_of
      return @photos_of if @photos_of

      # Make a dummy album
      album = Class.new {
        attr_reader :user
        def initialize(user, path)
          @user, @path = user, path
        end

        def path
          user.path + @path
        end
      }.new(self, 'photos_of')

      photos = GRAPH.get_object(@id + '?fields=photos.limit(200)')
      return [] unless photos['photos']

      @photos_of = PhotoIterator.new(GRAPH, album, photos)
    end

    def data
      @data ||= GRAPH.get_object(@id)
    end

    writeable :user, 'data.json', :data

    def name
      data['name']
    end

    def inspect
      "#<User #{name}>"
    end
  end
end

class Hall::Facebook
  command :update do
    bool :q, :quick, 'Skip when something old has been written'

    action do
      unless Config.has?(:facebook)
        puts "You must run facebook/init to authenticate first!"
        exit 2
      end

      token = Config.get(:facebook, :token)

      ::GRAPH = Koala::Facebook::API.new(token)

      break_on_skip = get(:quick)
      overwrite = {}

      me = Update::User.me

      puts "Me".bold
      me.write(overwrite)

      puts "Photos of Me".bold
      me.photos_of.each do |photo|
        break unless photo
        break if !photo.write(overwrite) && break_on_skip
      end

      puts "Albums".bold
      me.albums.each do |album|
        break unless album
        break if !album.write(overwrite) && break_on_skip
      end

      me.albums.each do |album|
        album.photos.each do |photo|
          break unless photo
          break if !photo.write(overwrite) && break_on_skip
        end
      end

      puts "Friends".bold
      me.connected_people.each do |person|
        person.write(overwrite)
      end

      puts "Albums I am in".bold
      me.connected_albums.each do |album|
        next if album.ignore?
        album.user.write(overwrite)
        break if !album.write(overwrite) && break_on_skip
      end

      me.connected_albums.each do |album|
        album.photos.each do |photo|
          break unless photo
          break if !photo.write(overwrite) && break_on_skip
        end
      end
    end
  end
end
