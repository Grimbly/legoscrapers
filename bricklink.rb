require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'sqlite3'

class Bricklink
	@@db = nil
	@@colors = nil
	
	# fetch set details from brickset.com
	def self.get_price(id, kind=:set, color=nil)
		begin
			# get data from web
			if kind == :set # it's a set: http://www.bricklink.com/catalogPG.asp?S=2283-1
				html = Nokogiri::HTML(open("http://www.bricklink.com/catalogPG.asp?S=#{id}-1-&colorID=0&v=D&viewExclude=Y&cID=Y"))
			elsif kind == :part # it's a part: http://www.bricklink.com/catalogPG.asp?P=87747&colorID=11
				html = Nokogiri::HTML(open("http://www.bricklink.com/catalogPG.asp?P=#{id}&colorID=#{color}"))
			elsif kind == :minifig # minifig: http://www.bricklink.com/catalogPG.asp?M=njo017
				html = Nokogiri::HTML(open("http://www.bricklink.com/catalogPG.asp?M=#{id}"))
			end
			
			# OH REALLY!? table galore!
			min_price = parse_price(html.xpath("/html/body/center/table[3]/tr/td/table/tr/td/table/tr/td/table[3]/tr[3]/td[3]/table/tr/td/table/tr[3]/td[2]/b").first.content)
			avg_price = parse_price(html.xpath("/html/body/center/table[3]/tr/td/table/tr/td/table/tr/td/table[3]/tr[3]/td[3]/table/tr/td/table/tr[4]/td[2]/b").first.content)
			max_price = parse_price(html.xpath("/html/body/center/table[3]/tr/td/table/tr/td/table/tr/td/table[3]/tr[3]/td[3]/table/tr/td/table/tr[6]/td[2]/b").first.content)
			last_sold = parse_price(html.xpath("/html/body/center/table[3]/tr/td/table/tr/td/table/tr/td/table[3]/tr[4]/td/table[3]/tr/td/table/tr[2]/td[3]").first.content)
			return [avg_price, min_price, max_price, last_sold]
		rescue
			return nil
		end
	end

	# returns array of triplets [qty, part_id, name(inc. color)]
	def self.get_parts(id)
		begin
			html = Nokogiri::HTML(open("http://www.bricklink.com/catalogItemInv.asp?S=#{id}-1"))
			parts = []
			qty = html.xpath "/html/body/center/table[3]/tr/td/table/tr/td/table/tr/td/table[2]/tr/td/center/form/table/tr/td[2]"
			ids = html.xpath "/html/body/center/table[3]/tr/td/table/tr/td/table/tr/td/table[2]/tr/td/center/form/table/tr/td[3]"
			names = html.xpath "/html/body/center/table[3]/tr/td/table/tr/td/table/tr/td/table[2]/tr/td/center/form/table/tr/td[4]"
			1.upto(qty.size-1) do |i| # first row is the header
				begin
					qty[i].content =~ /(\d+)/
					parts << [$1, ids[i].children[1].children.text.strip, names[i].children[0].text.strip]
				rescue
				end
			end
			return parts
		rescue
			return nil
		end
	end

	# sums the market value of all the individual set parts
	def self.get_parts_prices(id, only_minifigs=false)
		total = 0
		total_min = 0
		# get part list
		parts = self.get_parts(id)
		parts.each do |part|
			#puts part[2]
			begin
				colorid = self.match_color(part[2])
				# FIXME - we're assuming it's a minifig if no color matches. may be dangerous. we should check the get param
				
				next if only_minifigs and colorid
				
				if colorid # parse part price page
					prices = self.get_price(part[1],:part, colorid)
				else # parse minifig price
					prices = self.get_price(part[1],:minifig)
				end
				
				# value = qty * price_per_part(avg)
				value = part[0].to_i * prices[0]
				value_min = part[0].to_i * prices[1]
				
				# puts "#{part[2]}: #{part[0]} * #{prices[0]} = #{value}"
				
				# add to the total
				total += value
				total_min += value_min
			
			rescue # TODO
				#puts " ******* BODE! "
			end
		end
		return total, total_min
	end

	def self.set_ids_by_year(year=2012)
		ids = []
		page = 1
		results = nil
		loop do 
			html = Nokogiri::HTML(open("http://www.bricklink.com/catalogList.asp?pg=#{page}&itemYear=#{year}&sortBy=P&sortAsc=D&catType=S"))
			if results.nil?
				results = html.xpath("/html/body/center/table[3]/tr/td/table/tr/td/table/tr/td/table[1]/tr[3]/td/font/b[1]").text.to_i
				results = (results/50.0).ceil
			end
			html.css("td a").each do |a|
				ids << a.text if a.text.strip =~ /^\d+-1$/
			end
			break if page >= results
			page += 1
		end
		return ids
	end
	
	def self.parse_price(price)
		# sometimes bricklink returns EUR, other time USD... :x
		price.strip =~ /(\$?)([\d|\.|,]+)/
		if $1.any? # dollars
			return $2.gsub(',','').to_f * 0.75
		else # euros
			return $2.gsub(',','').to_f
		end
	end
	
	# saves this price to the db. price = [average, min, max, last_sold]
	def self.save_price(id, price, day=Time.now)
		# :set_id, :day, :average
		self.database.execute "insert into prices values (#{id}, #{day.strftime('%Y-%m-%d')}, #{price[0]}, #{price[1]}, #{price[2]}, #{price[3]});"
	end

	# matches a color code with the begining of the given string
	def self.match_color(description)
		self.colors.each do |c|
			if description.start_with?(c[0])
				return c[1]
			end
		end
		return nil
	end
	
	protected
	
	def self.database
		@@db ||= SQLite3::Database.new('database.db')
		@@db.type_translation = true
		return @@db
	end

	# load color codes from txt file
	def self.colors
		return @@colors if @@colors
		@@colors = []
		File.open("colors.txt", "r") do |infile|
  			while (line = infile.gets)
  				line =~ /(\d+)\s([\w\s-]+)/
  				@@colors << [$2.strip, $1.strip]
  			end
  		end
  		# sort by descending color name size
  		# maybe this will fix partial matching problems: "Reddish Brown" -> "Red"
  		@@colors = @@colors.sort{|a,b| b[0].size <=> a[0].size}
  		return @@colors
	end
end