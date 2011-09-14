require 'nokogiri'
require 'json'
require 'Set'
require 'test/unit'

module HQMFParse
  class HQMFFileParse
    @@outfp = nil
    @@idoutfp = nil
    @@idinfp = nil
    @@templates = nil
    @@doc = nil
    @@measure = {}
    @@relative_timings = Set.new(['SBS', 'SBE', 'EAS','SAE','DURING'])
    @@ids = {}
    def self.process_file(infile, outfile)
            STDOUT.puts "infile = #{infile} outfile = #{outfile}"
             @@templates = JSON.parse(File.open("hqmf_templates.json").read)
      #      STDOUT.puts JSON.pretty_generate(@@templates)
             @@idinfp = File.open(infile + ".map.json","r")
             STDOUT.puts "Map file should be in #{infile}.map.json -- #{@@idinfp}"
             @@doc = Nokogiri::XML(File.open(infile))
             @@doc.root.add_namespace_definition('rim', 'urn:hl7-org:v3')   
            if File.exist?(infile + ".map.json")   # we have a map file
               @@ids = JSON.parse(File.open(infile + ".map.json","r").read)
             else
             process_measure_attributes
             process_dataspec
#             @@ids.each_key do |key|
#               STDOUT.puts "key:#{key}  #{key.length} title:#{@@ids[key]['title']}"
 #            end
             @@idoutfp = File.open(outfile + ".map.json","w")
             @@idoutfp.puts JSON.pretty_generate(@@ids)
             @@idoutfp.close
            end
             ipp = @@doc.xpath("//rim:entry/rim:observation/rim:value[@code='IPP']")
             process_section(ipp,"IPP",outfile)
             denom = @@doc.xpath("//rim:entry/rim:observation/rim:value[@code='DENOM']")
             process_section(denom,"DENOM",outfile)
             numer = @@doc.xpath("//rim:entry/rim:observation/rim:value[@code='NUMER']")
             process_section(numer,"NUMER",outfile)
             STDOUT.puts JSON.pretty_generate(@@measure)
    end
     

=begin
<measureAttribute>
   <templateId root="2.16.840.1.113883.3.560.1.75"/>
   <id root="ED68061B-FC87-4233-82F8-BEE563126211"/>
   <code code="MSRED" displayName="Measurement end date" codeSystem="2.16.840.1.113883.3.560"/>
   <value xsi:type="TS" value="00001231"/>
</measureAttribute>
=end
    def self.addId(key, entry, title, template)
      STDOUT.puts "adding key:#{key}  title:#{title} template:#{template}"
      @@ids[key.strip] = {'entry' => entry, 'title' => title.strip, 'template' => template.strip, 'ph_id' => ""}
    end
    def self.process_measure_attributes
      attributes = @@doc.xpath("//rim:measureAttribute")
      i = 0
        STDOUT.puts "****MeasureAttributes*** #{attributes.length}"
        attributes.each do |attribute|
         id = attribute.at_xpath("./rim:id")
        templateID = attribute.at_xpath("./rim:templateId")
        if( id && templateID)
          i = i + 1
          display_string = attribute.at_xpath("./rim:code")['displayName']
          id_string = id['root']
          templateID_string = templateID['root']
          addId(id_string, attribute, display_string, templateID_string)
        end
      end
    end
    def self.process_dataspec
        STDOUT.puts "****DataSpecs***"
        dataspec = @@doc.xpath("//rim:section/rim:code[@code='57025-9']")
#        STDOUT.puts dataspec
        entries = dataspec.xpath("../rim:entry")
        entries.each do |entry|
           if entry.at_xpath("./*/rim:templateId")
            template_id = entry.at_xpath("./*/rim:templateId")['root']
             template_string = "template = #{template_id} #{@@templates[template_id]["description"]}  "
           end
           id_string = ""
           title = ""
           title_string = ""
           if(entry.at_xpath(".//rim:title"))
             title = entry.at_xpath(".//rim:title").content
             title_string = "title = #{title}"
           end
           if entry.at_xpath("./*/rim:id")
             id = entry.at_xpath("./*/rim:id")
             actualId = id['root']
             id_string = "id = #{actualId}"
             addId(actualId, entry, title, template_id)
             
           end
        end
        


    end
     def self.process_section(section,text,outfile)
       # add ID of the section to the @@ids hash
      i = 0
      nextsectionName = ""
      id_value = section.at_xpath("../rim:id")['root']
       title = section.at_xpath("../rim:value")['displayName']
       addId(id_value, section, title, "")
      @@measure[text] = {'name' => text }
      @@measure[text]['children'] = []
       sourceOfs = section.xpath("../rim:sourceOf")
      STDOUT.puts "****#{text}*** #{sourceOfs.length}"
              if sourceOfs.length > 0 
                  sourceOfs.each do |sourceOf|
                    nextsectionName = "#{text}.#{i}"
                    STDOUT.puts "nextsectionName = #{nextsectionName}"
                    @@measure[text]['children'][i] = {}
                    process_clause(sourceOf,0,@@measure[text]['children'][i] , nextsectionName)
                    i = i + 1
                  end
                end
     end
    
     def self.indent(level)
       tabs = ""
       level.times do
         tabs += "\t"
       end
       tabs
     end
     
    def self.process_relative_timing (top, level, topHash, clauseName)
       inversionInd = ""
       if top['inversionInd']
         inversionInd = "*invert*"
         topHash['inversionInd'] = inversionInd
        end
       typecode = top['typeCode']
       topHash['typecode'] = typecode
       topHash['level'] = level

#       topHash['clause'] = top

       observation = top.at_xpath("./rim:observation|./rim:act")
       if(observation)
          idnode = observation.at_xpath("./rim:id")
          if idnode
            id = idnode['root']
            id_title = @@ids[id]['title']
            ph_id = @@ids[id]['ph_id']
            topHash['ph_id'] = ph_id
          else
            id = "id:none"
          end
           titlenode  = observation.at_xpath("./rim:title")
           if titlenode
             title = titlenode.content
             topHash['title'] = title
           end
           if (titlenode && id_title != title)
             STDOUT.puts "id = #{id} title = #{title} (#{title.length}) != #{id_title} (#{id_title.length})"
             raise "PROBLEM title != id_title) "
           end         
       end

        STDOUT.puts "#{indent(level)} #{typecode}(#{level}) #{inversionInd}:    id = #{id}   ph_id=#{ph_id} "#title = #{id_title}"
        pauseQuantity = top.at_xpath("./rim:pauseQuantity")
         if(pauseQuantity)
         low = pauseQuantity.at_xpath("./rim:low")
          if(low)
              value = low['value']
              unit = low['unit']
              inclusive = low['inclusive']
              STDOUT.puts "#{indent(level)}       pauseQuantity low value = #{value} unit = #{unit} inclusive = #{inclusive}"
              topHash['low'] = { 'value' => value, 'unit' =>unit, 'inclusive' => inclusive}
          end
         high = pauseQuantity.at_xpath("./rim:high")
         if(high)
           value = high['value']
           unit = high['unit']
           inclusive = high['inclusive']
           STDOUT.puts "#{indent(level)}          pauseQuantity high  value = #{value} unit = #{unit} inclusive = #{inclusive}"
              topHash['high'] = { 'value' => value, 'unit' =>unit, 'inclusive' => inclusive}
            end
        end

    end
    def self.process_clause(top,level,topHash, clauseName)
      indent = ""
      conj_code = ""
      subs_code = ""
      id_string = ""
      title = ""
      template_id = ""
      template_string = ""
      temp = ""
      if top.at_xpath("./rim:conjunctionCode")
        actual_conj = top.at_xpath("./rim:conjunctionCode")['code']
        conj_code = "conj = #{actual_conj}"
        topHash['conj_code'] = actual_conj
      end
      if top.at_xpath("./rim:subsetCode")
        actual_subs = top.at_xpath("./rim:subsetCode")['code']
        subs_code = "subs = #{actual_subs}"
        topHash['subs_code'] = actual_subs
      end

      typecode = top['typeCode']
      topHash['name'] = clauseName
      topHash['typecode'] = typecode
      topHash['level'] = level
        case typecode 
        when "REFR"
          # not sure what this means...has to do with status
          added_self = false
          return(false)
          when "PRCN"
            id = top.at_xpath("./*/rim:id")
             if (id)
                actualId = id['root']
                id_string = "id = #{actualId} "
                 title = "#{@@ids[actualId]['title']}"
                 ph_id = @@ids[actualId]['ph_id']
                 topHash['ph_id'] = ph_id
                topHash['title'] = title
              end
              template = top.at_xpath("./*/rim:templateId")
              if(template)
               template_id = template['root']
                template_string = "template = #{@@templates[template_id]["description"]}"
              end

            STDOUT.puts "#{indent(level)}PRCN(#{clauseName}):  #{conj_code} #{id_string} #{ph_id}" # #{title} #{subs_code}  #{template_string} "   
            topHash['name'] = clauseName
            topHash['typecode'] = typecode
            topHash['level'] = level 
#            topHash['clause'] = top
             
=begin
            <sourceOf typeCode="PRCN">
                 <conjunctionCode code="AND"/>
                 <act classCode="ACT" moodCode="EVN" isCriterionInd="true">
                    <repeatNumber>
                       <low value="2" inclusive="true"/>
                    </repeatNumber>

=end
                      repeat = ""
                        repeatNode = top.at_xpath("./rim:act/rim:repeatNumber")
                      if(repeatNode)
                        topHash['repeatNumber'] = {}
                        low = repeatNode.at_xpath("./rim:low")
                         if(low)
                             value = low['value']
                              inclusive = low['inclusive']
                              STDOUT.puts "#{indent(level)}       Repeat low value = #{value}  inclusive = #{inclusive}"
                              topHash['repeatNumber']['low'] = {'value' => value, 'inclusive' => inclusive}
                         end
                         
                        high = repeatNode.at_xpath("./rim:high")
                        if(high)
                          value = high['value']
                          unit = high['unit']
                          inclusive = high['inclusive']
                          STDOUT.puts "#{indent(level)}          Repeat high  value = #{value}  inclusive = #{inclusive}"
                          topHash['repeatNumber']['high'] = {'value' => value, 'inclusive' => inclusive}
                          end
                       end
                 added_self = true
          when "COMP"

          STDOUT.puts "#{indent(level)}COMP(#{clauseName}):"  
          topHash['name'] = clauseName
          topHash['typecode'] = typecode
          topHash['level'] = level 
          added_self = true
          else
            if @@relative_timings.member?(typecode)
              self.process_relative_timing(top,level,topHash, clauseName)
              added_self = true
            else
              raise "#{indent(level)}  unknown typecode #{typecode}"
            end
          end
        
      clauses = top.xpath("./*/rim:sourceOf")
      j = 0
      if(clauses.length == 0)
        return added_self
      else
          topHash['children'] = []
      end
      clauses.each do |clause|
        nextName = "#{clauseName}.#{j}"
        topHash['children'][j] = {}
        nextHash = topHash['children'][j]
        added_child = process_clause(clause, level+1, nextHash, nextName)
        if(added_child)
          j = j + 1
        end
        STDOUT.puts "j = #{j}   added_child = #{added_child}"
      end
      if(j == 0)
        topHash.delete('children')
      end
      return (added_self || j > 0)
    end

   end
  class HQMFDirParse
    def self.process(indir, outdir)
      # Find all data defintion templates
      @@outdir = outdir
      gtemplateIDs = {}
      Dir.glob("#{indir}/*.{xml,XML}") do |item|
        infile = "#{item}"
        filebase = File.basename(infile) 
        outfile = "#{outdir}/#{filebase}"
        STDOUT.puts "infile  = #{item}  infilename = #{infile} outfile = #{outfile}"
        STDOUT.puts "Processing #{item}"
        process_file(infile,outfile)
      end
    end
    def self.process_file(infile, outfile)
      HQMFFileParse::process_file(infile,outfile)
    end
  end
end

# if launched as a standalone program, not loaded as a module
if __FILE__ == $0
  HQMFParse::HQMFDirParse.process(ARGV[0],ARGV[1])
end

