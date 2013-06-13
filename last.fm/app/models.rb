class Artist
  include DataMapper::Resource

  property :id,    Serial
  property :mbid,  String
  property :name,  String

  has n, :plays
end

class Album
  include DataMapper::Resource

  property :id,    Serial
  property :mbid,  String
  property :name,  String

  has n, :plays
end

class Play
  include DataMapper::Resource

  property :id,    Serial
  property :name,  String
  property :mbid,  String
  property :url,   String
  property :date,  DateTime

  belongs_to :artist
  belongs_to :album
end
