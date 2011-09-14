require 'nokogiri'
require 'json'

module HQMFParse

  class HQMFFileParse
    def self.process(infile, outfile)
      STDERR.puts "infile = #{infile} outfile = #{outfile}"
      outfp = File.open(outfile,"w")
      # make outfp a class variable
      doc = Nokogiri::XML(File.open(infile))
      doc.root.add_namespace_definition('rim', 'urn:hl7-org:v3')
      findTemplates(doc)
   end
    def self.findTemplates(doc)
      templates = doc.xpath("//rim:templateId")
      STDERR.puts "Found #{templates.length} templates  GORK"
       templates.each do |x|
        STDERR.puts "#{x}"
      end
    end
 
  end
  class HQMFDirParse
    @@results = []
    def self.process(indir, outdir)
      @@results = []
      @@outdir = outdir
      patient_num = 0
      Dir.glob("#{indir}/*.{xml,XML}") do |item|
        infile = "#{item}"
        filebase = File.basename(infile) 
        outfile = "#{outdir}/#{filebase}"
        STDERR.puts "infile  = #{item}  infilename = #{infile} outfile = #{outfile}"

        STDERR.puts "Processing #{item}"
        @@results << HQMFParse::HQMFFileParse.process(infile,outfile)
      end 
    end
 
  end
end

# if launched as a standalone program, not loaded as a module
if __FILE__ == $0
  HQMFParse::HQMFDirParse.process(ARGV[0],ARGV[1])
  STDERR.puts "I'm running"

end