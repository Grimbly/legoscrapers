require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'sqlite3'

class Brickset
	
	@@db = nil # database / cache
	
	class Set
		attr_accessor :id, :name, :year, :pieces, :rrp, :rrpp, :rrpd, :score, :theme, :subtheme, :picture, :paid
		
		def initialize(id, auto_save=true, force_refresh=false)
			# check if this set is in the db
			if (!force_refresh and (set=Brickset.database.get_first_row("select * from sets where id = #{id};")))
				map_from_db(set)
			else
				refresh_from_web(id)
				save! if auto_save # auto save to db
			end
		end
		
		# fetch set details from brickset.com
		def refresh_from_web(id)
			begin
				# get data from web
				self.id = id
				# fetch brickset page
				html = Nokogiri::HTML(open("http://www.brickset.com/detail/?Set=#{id}-1"))
				
				# parse set name
				name = html.css("#pageTitle h1").first.content.strip
				name =~ /[\d|\s]+:(.+)/
				self.name = $1.strip
				
				# parse brickset details
				details = html.css("#menuPanel .menuPanel .setDetails li")
				details.each do |detail|
					set_property(detail)
				end
				
				begin
					# parse review score
					score = html.css(".score").first.content
					self.score = score.strip
				rescue
					self.score = 0
				end
				
				# set rrp in eur
				if self.rrpp and self.rrpd # use avg between dollars and bgp
					self.rrp = ((self.rrpp.to_f * 1.25)+(self.rrpd.to_f * 0.75))/2.0
				elsif self.rrpp
					self.rrp = (self.rrpp.to_f * 1.25).to_f
				elsif self.rrpd
					self.rrp = (self.rrpd.to_f * 0.75).to_f
				else
					self.rrp = 0
				end
				
				# picture - TODO: is this reliable?
				self.picture = "http://www.1000steine.com/brickset/images/#{self.id}-1.jpg"
			rescue
			end
		end
		
		# map object attrs from the fetched db row
		def map_from_db(set)
			return false unless set
			# :id, :name, :year, :pieces, :rrp, :score, :theme, :subtheme
			self.id = set[0]
			self.name = set[1]
			self.year = set[2]
			self.pieces = set[3]
			self.rrp = set[4]
			self.score = set[5]
			self.theme = set[6]
			self.subtheme = set[7]
			self.picture = set[8]
			self.rrpd = set[9]
			self.rrpp = set[10]
			self.paid = set[11]
			return true
		end
		
		# saves this instance to the database
		def save!
			# is it already in the database? 
			if (set=Brickset.database.get_first_row("select * from sets where id = #{self.id};"))
				Brickset.database.execute "update sets set name='#{e self.name}', year=#{self.year}, pieces=#{self.pieces}, rrp=#{self.rrp||0}, score=#{self.score||0}, theme='#{e self.theme}', subtheme='#{e self.subtheme}', picture='#{self.picture}', rrpd=#{self.rrpd||0}, rrpp=#{self.rrpp||0}, paid=#{self.paid||0} where id = #{self.id};"
			else
				Brickset.database.execute "insert into sets values (#{self.id}, '#{e self.name}', #{self.year}, #{self.pieces}, #{self.rrp||0}, #{self.score||0}, '#{e self.theme}', '#{e self.subtheme}', '#{self.picture}', #{self.rrpd||0}, #{self.rrpp||0}, #{self.paid||0});"
			end
		end

		def paid?
			self.paid and self.paid > 0
		end
		
		def to_s
			"#{self.id},#{self.name},#{self.theme},#{self.year},-,#{self.rrp}"
		end
		
		protected
		
		# set a brickset property from the nokogiri html node
		def set_property(li)
			begin
				attribute = li.children.first.content.strip
				value = li.children[li.children.size-1].content.strip
				case attribute
				when "Theme"
					self.theme = value
				when "Subtheme"
					self.subtheme = value
				when "Year released"
					self.year = value
				when "Pieces"
					self.pieces = value
				when "RRP"
					value =~ /([\d|\.]+).+\$([\d|\.]+)/
					self.rrpp = $1.to_f
					self.rrpd = $2.to_f
				end
			rescue
			end
		end

		# escape string for db
		def e(s)
			s.gsub(/'/,'')
		end
	end
	
	def self.database
		@@db ||= SQLite3::Database.new('database.db')
		@@db.type_translation = true
		return @@db
	end
	
	def self.all
		sets = []
		Brickset.database.execute("select * from sets;").each do |set|
			# stupid: atm initialize is fetching each set _again_ from the db
			sets << Set.new(set[0])
		end
		return sets
	end
	
	def self.page(page=1)
		limit = 10
		offset = (page-1)*limit
		sets = []
		Brickset.database.execute("select * from sets limit #{limit} offset #{offset};").each do |set|
			# stupid: atm initialize is fetching each set _again_ from the db
			sets << Set.new(set[0])
		end
		return sets
	end
end