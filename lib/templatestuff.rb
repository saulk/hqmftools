def self.process_templates(infile, outfile,notitle_templates)
  @@notitle_templates = notitle_templates
  STDERR.puts "infile = #{infile} outfile = #{outfile}"
  outfp = File.open(outfile,"w")
  # make outfp a class variable
  doc = Nokogiri::XML(File.open(infile))
  doc.root.add_namespace_definition('rim', 'urn:hl7-org:v3')
  findTemplates(doc)
end
def self.findTemplates(doc)
  templateIDs = {}
  templates = doc.xpath("//rim:section/rim:entry/rim:act/rim:templateId")
STDERR.puts "Found #{templates.length} templates  GORK"
   templates.each do |template|
     STDERR.puts template
      title = template.at_xpath("..//rim:title")
      STDERR.puts "template: #{template}"
      STDERR.puts "title:   #{title}"
      if title
        content = title.content
      else
        content = "empty:"
      end
  shortcontent = content.split(':')[0]
  STDOUT.puts "#{template['root']} title: #{shortcontent}"
  if !content.eql?("empty:")
    if templateIDs[template['root']]
     templateIDs[template['root']][:instances]<< content.split(": ")[1]
    else
      templateIDs[template['root']] = { :description => content.split(": ")[0],
                                        :instances => [content.split(": ")[1]]
                                      }
    end
  else
    @@notitle_templates << template['root']
    STDOUT.puts "NO DESCRIPTION template: #{templateIDs[template['root']]}"
  end
  end
  templateIDs.sort
  templateIDs
end







  def self.process_templates(infile, outfile, notitle_templates)

        templateIDs = HQMFFileParse::process(infile,outfile,@@notitle_templates)

        templateIDs.each_pair do |key, value|
          if gtemplateIDs[key]
            gtemplateIDs[key][:instances] = (gtemplateIDs[key][:instances] + value[:instances]).uniq.sort
          else
            gtemplateIDs[key] = value
          end

        end
           STDOUT.puts "AFTER MERGE"
              gtemplateIDs.each_pair do |key,value|
                 STDOUT.puts "key = #{key}"
                 STDOUT.puts "value = #{value}"
              end
      end 
#      gtemplateIDs.each_key do |key|
#         STDERR.puts key
#       end
      @@notitle_templates.uniq.sort
      @@notitle_templates.each do |template|
        STDERR.puts "template: #{template}:  #{gtemplateIDs[template]}"
        if !gtemplateIDs[template]
          !gtemplateIDs[template] = {:description => "empty"}
        end
      end
        STDOUT.puts JSON.pretty_generate(gtemplateIDs)
    end
   end