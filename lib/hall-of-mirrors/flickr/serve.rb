#!/usr/bin/env ruby

gem 'sass'; require 'sass'
require 'haml'
require 'json'
require 'time'
require 'maruku'
require 'sinatra/base'
require 'seq/pager'
require 'launchy'
require 'tree'

class Hall::Flickr::Serve < Sinatra::Base
  PAGE_SIZE = 10

  # Requires #photos method to be defined
  module Pageable
    def __pages
      ivar = self.instance_variable_get(:@__pages)
      return ivar if ivar
      self.instance_variable_set(:@__pages, Seq::Pager.new(PAGE_SIZE, photos))
    end

    def page(num)
      __pages.page = num
      __pages.curr
    end

    def page_count
      __pages.pages
    end

    def range
      __pages.range(2, 2, 2)
        .reject(&:empty?)
        .map {|a| a << nil }
        .flatten.tap(&:pop)
    end
  end

  class GenericPageable
    include Pageable
    attr_reader :url, :photos

    def initialize(url, photos)
      @url = url
      @photos = photos
    end
  end


  class Photo
    attr_reader :id

    def initialize(user, id)
      @user  = user
      @id    = id
    end

    def name
      data['title']
    end

    def sort_date
      Time.at(data["dateuploaded"].to_i)
    end

    def index
      @user.index_of(self)
    end

    def prev
      @prev ||= begin
                  return if index <= 0
                  @user.find_by_index(index - 1)
                end
    end

    def next
      @next ||= begin
                  return if index >= @user.photos.size - 1
                  @user.find_by_index(index + 1)
                end
    end

    def path
      @user.path + 'photos' + @id.to_s
    end

    def url
      @user.url + "/#{id}"
    end

    def original_url
      name = Pathname.glob(path + 'photo_o.*').first
      return thumbnail_url unless name
      '/' + name.relative_path_from(ROOT + 'flickr').to_s
    end

    def thumbnail_url
      '/' + path.relative_path_from(ROOT + 'flickr').to_s + '/photo_z.jpg'
    end

    def description
      data['description'].gsub("\n", "<br/>")
    end

    def data
      @data ||= JSON.parse File.read(path + 'data.json')
    end

    def exif
      @exif ||= JSON.parse File.read(path + 'exif.json')
    rescue
      {}
    end

    def has_exif?(name)
      get_exif(name) != nil
    end

    def get_exif(name)
      return unless exif['exif']

      exif['exif'].find {|t|
        t['label'] == name || t['tag'] == name
      }
    end

    def inspect
      "#<Photo #{@id}>"
    end

    def method_missing(sym, *args, &block)
      if data.key?(sym.to_s)
        data[sym.to_s]
      else
        super
      end
    end
  end

  class ExtendedPhoto < Photo
    attr_reader :extended_data

    def initialize(user, id, extended_data)
      @user = user
      @id = id
      @extended_data = extended_data
    end
  end


  class Set
    include Pageable

    attr_reader :id

    def initialize(user, id)
      @user = user
      @id   = id
    end

    def name
      data['title']
    end

    def path
      @user.path + 'sets' + id.to_s
    end

    def url
      @user.url + '/sets/' + id.to_s
    end

    def photos
      @photos ||= data['photos'].reverse.map {|ph| @user.photo(ph) }
    end

    def data
      @data ||= JSON.parse File.read(path + 'data.json')
    end

    def inspect
      "#<Set #@id>"
    end
  end

  class Tag
    include Pageable

    attr_reader :name

    def initialize(user, ids, name)
      @user = user
      @ids  = ids
      @name = name
    end

    def photos
      @photos ||= @ids.map {|ph| @user.photo(ph)}
    end

    def url
      @user.url + '/tags/' + @name
    end

    def inspect
      "#<Tag #@name>"
    end
  end

  class Camera
    include Pageable

    def initialize(user, ids, make, model)
      @user  = user
      @ids   = ids
      @make  = make
      @model = model
    end

    def name
      @make + " " + @model
    end

    def escaped_name
      name.downcase.gsub(' ', '-')
    end

    def photos
      @photos ||= @ids.map {|ph| @user.photo(ph) }
    end

    def url
      @user.url + '/cameras/' + escaped_name
    end

    def inspect
      "#<Camera #{name}>"
    end
  end

  class Place
    LEVELS = %w(country region county locality neighbourhood)
    include Pageable

    attr_reader :parent, :level, :data

    def initialize(user, level, data, parent=nil)
      @parent = parent
      @user   = user
      @data   = data
      @level  = level
      @ids    = []
    end

    def << photo
      @ids += [photo.id]
    end

    def id
      @data['woeid']
    end

    def name
      @data['_content']
    end

    def photos
      @photos ||= @ids.map {|ph| @user.photo(ph) }
    end

    def url
      @user.url + '/places/' + id
    end

    def inspect
      "#<Place #{name}>"
    end
  end

  class User
    include Pageable

    def self.all
      @all ||= Dir[ROOT + 'flickr' + '*@*'].map {|path|
        new path.split('/').last
      }
    end

    # term could be an id (nsid) or path_alias.
    def self.find(term)
      all.find {|user|
        user.id == term || user.data['path_alias'] == term
      }
    end

    attr_reader :id

    def initialize(id)
      @id = id
    end

    def name
      data['username']
    end

    def path
      ROOT + 'flickr' + @id.to_s
    end

    def data
      if (path + 'data.json').exist?
        @data ||= JSON.parse File.read(path + 'data.json')
      else
        {}
      end
    end

    def url
      "/photos/#{id}"
    end

    def url_for_page(num)
      "/photos/#{id}/page/#{num}"
    end

    def index_of(photo)
      photos.index(photo)
    end

    def find_by_index(index)
      photos[index]
    end

    def cameras
      return @cameras if @cameras

      @cameras = {}
      photos.each do |photo|
        make  = photo.get_exif('Make')
        model = photo.get_exif('Model')

        if make && !make.empty? && model && !model.empty?
          make = make['raw'].strip; model = model['raw'].strip
          @cameras[make] ||= {}
          @cameras[make][model] ||= []
          @cameras[make][model]  += [photo.id]
        end
      end

      @cameras = @cameras.map {|make, models|
        models.map {|model, ids|
          Camera.new(self, ids, make, model)
        }
      }.flatten
    end

    def camera(name)
      cameras.find {|ca| ca.escaped_name == name }
    end


    def faves
      return @faves if @faves

      faves = Dir[path + 'favorites' + '*'].map {|dir|
        JSON.load File.read(dir + '/data.json')
      }.sort_by {|data| -data['date_faved'].to_i }.map {|data|
        user = User.find(data['owner'])
        ExtendedPhoto.new(user, data['id'], data)
      }

      @faves = GenericPageable.new(self.url + '/faves', faves)
    end


    def tags
      return @tags if @tags

      @tags = Hash.new([])
      photos.each do |photo|
        next unless photo.data.has_key?('tags')
        next unless photo.data['tags'].has_key?('tag')

        photo.data['tags']['tag'].each do |tag|
          @tags[tag['_content']] += [photo.id]
        end
      end

      @tags = @tags.map {|k,v| Tag.new(self, v, k) }
    end

    def tag(name)
      tags.find {|tg| tg.name == name }
    end

    def sets
      @sets ||= Dir[path + 'sets' + '*'].map {|dir|
        Set.new(self, dir.split("/").last.to_i)
      }.compact
    end

    def set(id)
      sets.find {|st| st.id == id.to_i }
    end

    def photos
      @photos ||= Dir[path + 'photos' + '*'].map {|path|
        Photo.new(self, path.split("/").last.to_i)
      }.sort_by(&:sort_date).reverse
    end

    def photo(id)
      photos.find {|ph| ph.id == id.to_i }
    end

    def places
      return @places if @places

      @places = {}
      levels = Place::LEVELS

      photos.each do |photo|
        next unless loc = photo.data['location']

        parent = nil
        levels.each do |level|
          next unless data = loc[level]

          @places[data['woeid']] ||= Place.new(self, level, data, parent)
          @places[data['woeid']] << photo
          parent = @places[data['woeid']]
        end
      end

      root_node = Tree::TreeNode.new("root")

      countries = @places.find_all {|_,v| v.parent.nil? }
      countries.each do |_, country|
        country_node = Tree::TreeNode.new(country.id, country)

        regions = @places.find_all {|_,v| v.parent == country }
        regions.each do |_, region|
          region_node = Tree::TreeNode.new(region.id, region)

          counties = @places.find_all {|_,v| v.parent == region }
          counties.each do |_, county|
            county_node = Tree::TreeNode.new(county.id, county)

            localities = @places.find_all {|_,v| v.parent == county }
            localities.each do |_, locality|
              locality_node = Tree::TreeNode.new(locality.id, locality)

              neighbourhoods = @places.find_all {|_,v| v.parent == locality }
              neighbourhoods.each do |_, neighbourhood|
                neighbourhood_node = Tree::TreeNode.new(neighbourhood.id, neighbourhood)

                locality_node << neighbourhood_node
              end

              county_node << locality_node
            end

            region_node << county_node
          end

          country_node << region_node
        end

        root_node << country_node
      end

      @places = root_node
    end

    def place(woeid)
      places.find {|pl| pl.name == woeid }.content
    end

    def inspect
      "#<User #@id>"
    end
  end
end

def time(msg, &block)
  s = Time.now
  block.call
  puts "#{msg}: #{Time.now - s}s"
end


class Time
  # nicked from parallel-flickr, because it's nice
  # straup/parallel-flickr/www/include/lib_flickr_dates.php
  def descriptive_hour
    case hour
    when 0..6 then "after midnight"
    when 6..8 then "in the wee small hours of the morning"
    when 8..12 then "in the morning"
    when 12..14 then "around noon"
    when 14..18 then "in the afternoon"
    when 18..20 then "in the evening"
    else "at night"
    end
  end

  def ordinal
    case day
    when 1, 21 then "st"
    when 2, 22 then "nd"
    else "th"
    end
  end
end

class Hall::Flickr::Serve
  set :public_folder, File.dirname(__FILE__)
  set :views, File.dirname(__FILE__) + '/app'


  helpers do
    def short_time_from_string(d)
      time = Time.parse(d)
      day  = time.strftime("%B %-d") + time.ordinal + time.strftime(" %Y")
      "<time datetime=\"#{time.strftime("%FT%T%:z")}\">#{day}</time>"
    end

    def time_from_string(d)
      time = Time.parse(d)
      hour = time.descriptive_hour
      day  = time.strftime("%A %B %-d") + time.ordinal + time.strftime(" %Y")
      "<time datetime=\"#{time.strftime("%FT%T%:z")}\">#{day}, #{hour}</time>"
    end

    def title(*parts)
      parts = %w(flickr) + parts.map {|part|
        part.respond_to?(:name) ? part.name : part
      }
      parts.join(" / ")
    end

    def partial(page, options={})
      haml "partials/#{page}".to_sym, options.merge(:layout => false)
    end
  end


  get '/' do
    @users = User.all
    haml :users
  end

  get '/styles.css' do
    sass :styles
  end

  get '/photos/:user/?' do
    @user = User.find(params[:user])
    @page = 0
    @photos = @user.page(@page)
    haml :photos
  end

  get '/photos/:user/page/:num/?' do
    @user = User.find(params[:user])
    @page = params[:num].to_i

    redirect @user.url if @page == 0

    @photos = @user.page(@page)
    haml :photos
  end


  get '/photos/:user/faves/?' do
    @user   = User.find(params[:user])
    @faves  = @user.faves
    @page   = 0
    @photos = @faves.page(@page)

    haml :faves
  end

  get '/photos/:user/faves/page/:num/?' do
    @user   = User.find(params[:user])
    @faves  = @user.faves
    @page   = params[:num].to_i
    @photos = @faves.page(@page)

    redirect @user.url + '/faves' if @page == 0

    haml :faves
  end


  get '/photos/:user/cameras/?' do
    @user = User.find(params[:user])
    @cameras = @user.cameras

    haml :cameras
  end

  get '/photos/:user/cameras/:camera/?' do
    @user   = User.find(params[:user])
    @camera = @user.camera(params[:camera])
    @page   = 0
    @photos = @camera.page(@page)

    haml :camera
  end

  get '/photos/:user/cameras/:camera/page/:num/?' do
    @user   = User.find(params[:user])
    @camera = @user.camera(params[:camera])
    @page   = params[:num].to_i
    @photos = @camera.page(@page)

    redirect @camera.url if @page == 0

    haml :camera
  end


  get '/photos/:user/places/?' do
    @user = User.find(params[:user])
    @places = @user.places

    haml :places
  end

  get '/photos/:user/places/:woeid/?' do
    @user   = User.find(params[:user])
    @place  = @user.place(params[:woeid])
    @page   = 0
    @photos = @place.page(@page)

    haml :place
  end

  get '/photos/:user/places/:woeid/page/:num?' do
    @user   = User.find(params[:user])
    @place  = @user.place(params[:woeid])
    @page   = params[:num].to_i
    @photos = @place.page(@page)

    redirect @place.url if @page == 0

    haml :place
  end


  get '/photos/:user/sets/?' do
    @user = User.find(params[:user])
    @sets = @user.sets

    haml :sets
  end

  get '/photos/:user/sets/:set/?' do
    @user   = User.find(params[:user])
    @set    = @user.set(params[:set])
    @page   = 0
    @photos = @set.page(@page)

    haml :set
  end

  get '/photos/:user/sets/:set/page/:num/?' do
    @user   = User.find(params[:user])
    @set    = @user.set(params[:set])
    @page   = params[:num].to_i
    @photos = @set.page(@page)

    redirect @set.url if @page == 0

    haml :set
  end


  get '/photos/:user/tags/?' do
    @user = User.find(params[:user])
    @tags = @user.tags

    haml :tags
  end

  get '/photos/:user/tags/:tag/?' do
    @user   = User.find(params[:user])
    @tag    = @user.tag(params[:tag])
    @page   = 0
    @photos = @tag.page(@page)

    haml :tag
  end

  get '/photos/:user/tags/:tag/page/:num' do
    @user   = User.find(params[:user])
    @tag    = @user.tag(params[:tag])
    @page   = params[:num].to_i
    @photos = @tag.page(@page)

    redirect @tag.url if @page == 0

    haml :tag
  end


  get '/photos/:user/:photo/?' do
    @user  = User.find(params[:user])
    @photo = @user.photo(params[:photo])

    haml :photo
  end


  get '/:user/photos/:id/photo_z.jpg' do
    send_file ROOT + 'flickr' + params[:user] + 'photos' + params[:id] + 'photo_z.jpg'
  end

  get '/:user/photos/:id/photo_o.:ext' do
    send_file ROOT + 'flickr' + params[:user] + 'photos' + params[:id] +
      ('photo_o.' + params[:ext])
  end
end

class Hall::Flickr
  command :serve do
    action do
      sinatra_options = {
        :port => '4567',
        :bind => 'localhost',
      }

      Serve.run!(sinatra_options) do |server|
        ::Launchy.open("http://localhost:4567/")
      end
    end
  end
end
