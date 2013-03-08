require 'rubygems'
require 'nokogiri'
require 'open-uri'

class Amazon
	def self.get_price(set, amazon=:uk)
		begin
			doc = Nokogiri::HTML(open("http://brickset.com/ajax/setTabs/buy.aspx?set=#{set}-1"))
			# TODO - support all amazons
			doc.css('table.amazonBuy span.toPay').first.text =~ /[^\d]*([\d\.]+)/
			return $1.to_f*1.25 # in euros
		rescue
		end
		return nil
	end
end