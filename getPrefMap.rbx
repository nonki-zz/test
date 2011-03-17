#!/usr/bin/ruby

require 'postgres'
require 'cgi'
require '../vslib/maplib.rb'
require '../vslib/svglib.rb'

load '../vslib/vslib.rb'


class PrefMap

	include Svg

	attr_reader :svgelem
	attr_reader :svgscript
	attr_accessor :pathStyle
	attr_accessor :unionTable
	attr_accessor :areaNames

	class PGISconn < PGconn
	
	    PGIS_HOST = '192.168.10.240'
	    PGIS_DB = 'jatlas'
	    PGIS_UNAME = 'fujino'
	
	    def PGISconn.connect
	        PGconn.connect(PGIS_HOST, 5432, '', '', PGIS_DB, PGIS_UNAME, '')
	    end
	
	end

	def initialize(pcode, year, width=500, height=500)
		@width, @height = width, height
		@pcode = pcode
		@year = selectMapYear(year)
		@svgelem = SvgElem.new(@width, @height)
		@svgelem.viewBox = viewBox
		@svgscript = SvgScript.new
	end

	def getBorder
		if unionTable.nil? || areaNames.nil?
			return getDefaultBorder
		else
			return getCustomBorder
		end
	end

	def getCustomBorder
		conn = PGISconn.connect
		path = "<g id=\"prefmap\" style=\"#{pathStyle}\">\n"
		unionTable.each do |key, value|
			poly = conn.query <<-EOS
				select AsSVG(GeomUnion(the_geom)) from jp#{@year}.map
				where jcode/1000=#{@pcode} and jcode%1000 in (#{value.join(',')})
			EOS
			path << "<g id=\"#{key}\" city=\"#{areaNames[key]}\">\n\t<path d=\"#{poly.to_s}\" />\n</g>\n"
		end
		path << "</g>"
		conn.close
		return path
	end

	def getDefaultBorder
		conn = PGISconn.connect
		resGP = conn.query("select jcode,town2,AsSVG(the_geom) from jp#{@year}.map
							where jcode/1000=#{@pcode} order by jcode")
		conn.close
		path = ''
		preid = ''
		path << "<g id=\"prefmap\" style=\"#{pathStyle}\">" if pathStyle
		resGP.each do |line|
 			if preid != line[0]
				path << "\n</g>" if preid != ''
				path << "\n<g id=\"#{line[0].to_i%1000}\" city=\"#{line[1].strip}\">\n"
			end
			path << "<path d=\"#{line[2]}\" />"
			preid = line[0]
		end
		path << "\n</g>"
		path << "\n</g>" if pathStyle

		return path
	end

	def viewBox
		conn = PGISconn.connect
		resVB = conn.query("select extent(the_geom) from jp#{@year}.map
							where jcode/1000=#{@pcode}")
		conn.close
		bb0 = resVB[0][0]
		%r|(\(.*\))| =~ bb0
		
		bb = $1.gsub(/[\(\)]/,'').gsub(/,/,' ').split
		width = bb[2].to_f - bb[0].to_f
		height = bb[3].to_f - bb[1].to_f

		return "#{bb[0]} -#{bb[3]} #{width} #{height}"
	end



end 

class PrefMap2 < PrefMap

	def getCustomBorder
		conn = PGISconn.connect
		path = "<g id=\"prefmap\" style=\"#{pathStyle}\">\n"
		unionTable.each do |year, codehash|
			path << "<g id=\"year#{year}\">\n"
			codehash.each do |key, value|		
				poly = conn.query <<-EOS
					select AsSVG(GeomUnion(the_geom)) from jp#{@year}.map
					where jcode/1000=#{@pcode} and jcode%1000 in (#{value.join(',')})
				EOS
				path << "<g id=\"#{year}#{sprintf("%03d",key.to_i)}\" city=\"#{areaNames[key]}\">\n\t<path d=\"#{poly.to_s}\" />\n</g>\n"
			end
			path << "</g>\n"
		end
		path << "</g>"
		conn.close
		return path
	end
end

cgi = CGI.new
pref = cgi.params['pref'][0].to_i
year = cgi.params['year'][0].to_i
print cgi.header("type"=>"image/svg+xml", "charset"=>"utf-8")

pm = PrefMap2.new(pref,1900,500,500)

if cgi['funit']=='city'
	conn = PGISconn.connect
	uctable = conn.query <<-EOS
		select year, city_code, union_code from union_city
	    where pref_code=#{pref} and year>=#{selectMapYear(year)}
	    order by year , union_code, city_code 
	EOS
	pm.areaNames = jcode2name(pref)
	conn.close
else
    conn = VSconn.connect
    uctable = conn.query <<-EOS
        select #{year}, city_code, health_center_code from city_code
        order by health_center_code, city_code
    EOS
    conn.close
	pm.areaNames = hctable
end

pm.unionTable = makeUH(uctable, year,pref).sort_by{|key,value| key.to_i}
pm.pathStyle = "pointer-events:all; fill: none; stroke: black; stroke-width:0.001;"
pm.svgelem.onload = "init(evt);"
pm.svgscript.jsfiles << "prefmap.js"
print pm.xmlheader
print pm.svgelem.svgBegin
print pm.svgscript.putScript
print pm.getBorder
print <<EOF
<!--
#{pm.unionTable.inspect}
-->
EOF
print pm.svgelem.svgEnd

