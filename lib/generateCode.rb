
require 'json'
require 'Set'

module HQMFToCode

  class GenCodeDirParse
    def self.process(indir, outdir)
      # Find all data defintion templates
      @@outdir = outdir
      Dir.glob("#{indir}/NQF*.{json,JSON}") do |item|
        infile = "#{item}"
        filebase = File.basename(infile) 
        outfile = "#{outdir}/#{filebase}"
        STDOUT.puts "infile  = #{item}  infilename = #{infile} outfile = #{outfile}"
        STDOUT.puts "Processing #{item}"
        process_file(infile,outfile)
      end
    end
    def self.process_file(infile, outfile)
      HQMJSonCleanup::process_file(infile,outfile)
    end
  end
  class HQMJSonCleanup    
    @@relative_timings = Set.new(['SBS', 'SBE', 'EAS','SAE','SAS'])
    #@@relative_timings.member?(typecode)
    @@hqmfin = nil
    @@hqmfout = nil
    @@errfout = nil
    @@codefout = nil
    @@nodenum = 1
    @@change = false

    def self.process_file(infile, outfile)
      @@hqmfin = JSON.parse(File.open(infile).read)
      @@hqmfout = File.open(outfile,"w")
      codefile = outfile + ".code"
      errfile = outfile + ".err"
      @@codefout = File.open(codefile,"w")
      @@errfout = File.open(errfile,"w")
      @@errfout.puts "infile = #{infile} outfile = #{outfile}"
      @@hqmfin.each_pair do |key,value|
        #          if key != "EXCLUSION"
        #            next
        #          end
        @@errfout.puts "***Processing section #{key}" 
        @@emitted = {}  #hash of emitted names
        @@expressions_to_name = {}  # has of expressions to names
        self.COMPcleanup(value)
        self.labelDepth(value)
        self.labelType(value)
        @@change = true;
        @@codefout.puts "#*** Code for #{key}"
        @@codefout.puts "#{key}{"
        while(@@change)
          @@change = false
          self.mergeDateTimingInterval(value)
          self.mergeValueSets(value)
          self.labelDepth(value)
          self.mergeEventListDuringInterval(value)
          self.emitCode(value)
          self.labelDepth(value)
          self.mergeEventListTimingInterval(value)
          self.emitCode(value)
          self.labelDepth(value)
          self.mergeEventListDuringEventList(value)
          self.emitCode(value)
          self.labelDepth(value)
          self.mergeEventListTimingEventList(value)
          self.emitCode(value)
          self.labelDepth(value)
          self.mergeEventListTimingEventListFlat(value)
          self.emitCode(value)
          self.labelDepth(value)
          self.mergeEventListTimingEventListSibling(value)
          self.emitCode(value)
          self.labelDepth(value)
          @@errfout.puts "***End of loop...@@change = #{@@change}"
        end
        self.emitWrappingLogic(value)
        @@codefout.puts "}"
      end
      @@hqmfout.puts JSON.pretty_generate(@@hqmfin)
      @@hqmfout.close
    end

    def self.getNodeName (expression)      
      name = @@expressions_to_name[expression]
      if !name
        name = "n#{@@nodenum}"
        @@nodenum = @@nodenum + 1
        @@expressions_to_name[expression] = name
      end
      return name
    end

    def self.getEmitName(node)
      name = "(none)"
      case node['status']
      when 'none'
        name = node['ph_id']
      when 'emit'
        name = node['ph_id']
      when 'emitted'
        name = node['name']        
      else
        name = node['ph_id']
      end
      #        @@errfout.puts "getEmitName ph_id = #{node['ph_id']}  name = #{node['name']}  status = #{node['status']} ==> name = #{name}"
      return name
    end

    def self.emitWrappingLogic(section)
      first = true
      logic = "return("
      section['children'].each do |child|
        if child['status'] == 'emitted'
          if !first
            logic << " AND "
          end
          logic << "#{getEmitName(child)}"
          first = false
        end
      end
      logic << " )"
      @@codefout.puts logic     
    end
    def self.emitCode(section)
      # ultimately, look for different patterns here and have an emit method for each one
      if (section['status'] == "emit")
        @@errfout.puts "emitCode #{section['name']} status = #{section['status']} pattern = #{section['pattern']} type = #{section['type']} value = #{section['value']} depth = section['depth]"
        @@change = true
        if !@@emitted[section['name']]
          @@emitted[section['name']] = section['name']
          case section['pattern']
          when 'merged_value_sets'
            @@codefout.puts "#{section['name']} = #{section['value']}"
          when 'eventlistduringinterval'
            @@codefout.puts "#{section['name']} = #{section['value']}"
          when 'eventlisttiminginterval'
            @@codefout.puts "#{section['name']} = #{section['value']}"            
          when 'eventlistduringeventlist'
            @@codefout.puts "#{section['name']} = #{section['value']}"
          when 'eventlisttimingeventlist'
            @@codefout.puts "#{section['name']} = #{section['value']}"
          when 'eventlisttimingeventlistflat'
            @@codefout.puts "#{section['name']} = #{section['value']}"  
          when 'datetiminginterval'
            @@codefout.puts "#{section['name']} = #{section['value']}"   
          when 'eventlisttimingeventlistsibling'                     
            @@codefout.puts "#{section['name']} = #{section['value']}"   
          else
            raise "invalid pattern #{section['pattern']}"
          end
        end
        section['status'] = 'emitted'    # refer to this node by the value name, e.g. n3  
      elsif section['children']
        section['children'].each do |child|
          self.emitCode(child)
        end
      end
    end

    #get rid of COMP nodes that add nothing to the tree, just confuse the tree rewrite
    def self.COMPcleanup(section)
      if section['children']
        section['children'].each do |child|
          self.COMPcleanup(child)
        end
        if !section['children']
          return
        end
        if section['children'].length == 1
          child = section['children'][0]
          @@errfout.puts "Single child...typcode = #{child['typecode']}"
          if child['typecode'] == 'COMP'
            grandchildren = child['children']
            if (!grandchildren || grandchildren.length == 1)
              section['children'] = child['children']   #chop out the CMP
            end
          end
        end
      end
    end

    def self.labelDepth(section)
      max_depth = 0;
      if (section['status'] != 'emitted') & section['children']   # a node that has been emitted is the end of the line
        section['children'].each do |child|
          depth = self.labelDepth(child)
          if depth > max_depth
            max_depth = depth
          end
        end
      end
      section['maxDepth'] = max_depth
      return max_depth + 1
    end
    def self.labelType(section)
      type = 'unknown'
      # if we've assigned an expression, use it
      if section['value']
        type = "value"
      else
        @@errfout.puts "section #{section['ph_id']}"
        case section['ph_id']
        when 'measurement_period'
          type = "date_interval"
        when ''
          if section['title'] == "Initial Patient Population"
            type = "ignore"
          end
        when 'birthdate'
          type = "date_single"
        when 'measurement_period.start'
          type = "date_single"
        when 'measurement_period.end'
          type = "date_single"
        else
          if section['ph_id']
            if section['ph_id'][0, 8] == "measure."
              type = "event_list"
              section['value'] = section['ph_id']
            end
          end
        end
      end
      section['type'] = type
      if section['children']
        section['children'].each do |child|
          @@errfout.puts "#{child['name']}"
          self.labelType(child)
        end
      end
    end

    def self.extracttiming(timingnode)
      low = high = 0
      lowunits = highunits = "none"
      lowinclusive = highinclusive = "true"
      if(timingnode['high'])
        low = timingnode['high']['value']
        lowunits = timingnode['high']['unit']
        lowinclusive = timingnode['high']['inclusive']
      end        
      if(timingnode['low'])
        low = timingnode['low']['value']
        lowunits = timingnode['low']['unit']
        lowinclusive = timingnode['low']['inclusive']
      end
      if timingnode['inversionInd'] == "*invert*"
        invert = 'true'
      else
        invert = 'false'
      end
      subs_code = "NONE"
      if timingnode['subs_code']
          subs_code = timingnode['subs_code']
        end
      timinginfo = { 'low' => low, 'high' => high, 
        'lowunits' =>lowunits, 'highunits' =>highunits, 
        'lowinclusive' => lowinclusive, 'highinclusive' =>highinclusive,
        'invert' =>invert, 'typecode' => timingnode['typecode'], 'subs_code' => subs_code} 
        return timinginfo 
      end     

      def self.mergeDateTimingInterval(section)
        # if we've bottomed out, return
        if section['maxDepth'] == 0
          return
        end
        if section['maxDepth'] > 1
          section['children'].each do |child|
            self.mergeDateTimingInterval(child)
          end
        else   # depth = 1
          #pattern is node of type date_single with a child Timing(SBS, etc) that references a date_interval 
          # translation is n# = DateTimingInterval(date_single_value, interval.start, interval.end, timing (e.g., SBS), lowinterval, highinterval, lowunits, highunits, lowinclusive, highinclusive)
          # The type of the result is boolean
          if !section['children']
            raise "there should be children and there are none"
          end
          if section['children'].length > 1 
            return
          end
          timingchild = section['children'][0]
          low = high = 0
          lowunits = highunits = "none"
          lowinclusive = highinclusive = "true"
          if(timingchild['high'])
            low = timingchild['high']['value']
            lowunits = timingchild['high']['unit']
            lowinclusive = timingchild['high']['inclusive']
          end        
          if(timingchild['low'])
            low = timingchild['low']['value']
            lowunits = timingchild['low']['unit']
            lowinclusive = timingchild['low']['inclusive']
          end

          if (timingchild['type'] != 'date_interval') |
            (section['type'] != 'date_single') |
            (!@@relative_timings.member?(timingchild['typecode'])) 
            return
          end

          if timingchild['type'] == 'date_single'
            startdate = enddate = getEmitName(timingchild)
          else
            startdate = "#{getEmitName(timingchild)}.start"
            enddate = "#{getEmitName(timingchild)}.end"    
          end      

          @@errfout.puts "mergedatetiminginterval -- section #{section['name']} depth = #{section['maxDepth']} title #{section['title']} ph_id = #{section['ph_id']}"
          section['status'] = 'emit'
          section['pattern'] = 'datetiminginterval'
          section['value'] =  "dateTimingInterval(#{section['ph_id']}, #{startdate}, #{enddate}, #{timingchild['typecode']}, #{low}, #{high} #{lowunits}, #{highunits}, #{lowinclusive}, #{highinclusive} )"
          section['name'] = getNodeName(section['value'])

        end  
      end

      # We are looking for an event list (e.g., activeDiabetes) during in interval (e.g., measurement period)
      def self.mergeEventListTimingInterval(section)
         @@errfout.puts "mergeEventListTimingInterval -- section depth = #{section['maxDepth']} title #{section['title']} ph_id = #{section['ph_id']}"
        # if we've bottomed out, return
        if section['maxDepth'] == 0
          return
        end
        if section['maxDepth'] > 1
          section['children'].each do |child|
            self.mergeEventListTimingInterval(child)
          end
        else   # depth = 1
          #pattern is typecode PRCN for this node, type event_list
          # single child must be typecode DURING and type date_interval
          # translation is n# = EventsDuring(value, interval.start, interval,end)
          if !section['children']
            raise "there should be children and there are none"
          end
          if section['children'].length > 1
            @@errfout.puts "Too many children #{section['children'].length}"
            return
          end
          child = section['children'][0]
          @@errfout.puts "$$$ section type = #{section['type']} sectiontypecode = #{section['typecode']}  childtypecode = #{child['typecode']}"
          if ( section['type'] == 'event_list') &
            ( @@relative_timings.member?(child['typecode'] ) ) &
            ( (child['type'] == 'date_interval') || (child['type'] == 'date_single'))

            @@errfout.puts "mergeEventListTimingInterval -- section depth = #{section['maxDepth']} title #{section['title']} ph_id = #{section['ph_id']}"
            if child['type'] == 'date_single'
              startdate = enddate = getEmitName(child)
            else
              startdate = "#{getEmitName(child)}.start"
              enddate = "#{getEmitName(child)}.end"    
            end      
            timinginfo = self.extracttiming(child)
            section['status'] = 'emit'
            section['pattern'] = 'eventlisttimingeventlist'
            section['value'] =  "eventsTimingEvents(#{getEmitName(section)}, #{startdate}, #{enddate}, #{timinginfo['invert']},#{timinginfo['typecode']}, #{timinginfo['low']},#{timinginfo['high']}, #{timinginfo['lowunits']}, #{timinginfo['highunits']}, #{timinginfo['lowinclusive']}, #{timinginfo['highinclusive']})"
            section['name'] = getNodeName(section['value'] )
            section['type'] = 'event_list'
           end  
        end
      end

      # We are looking for an event list (e.g., activeDiabetes) during in interval (e.g., measurement period)
      def self.mergeEventListDuringInterval(section)
        #  @@errfout.puts "mergeEventListDuringInterval -- section depth = #{section['maxDepth']} title #{section['title']} ph_id = #{section['ph_id']}"
        # if we've bottomed out, return
        if section['maxDepth'] == 0
          return
        end
        if section['maxDepth'] > 1
          section['children'].each do |child|
            self.mergeEventListDuringInterval(child)
          end
        else   # depth = 1
          #pattern is typecode PRCN for this node, type event_list
          # single child must be typecode DURING and type date_interval
          # translation is n# = EventsDuring(value, interval.start, interval,end)
          if !section['children']
            raise "there should be children and there are none"
          end
          if section['children'].length > 1
            return
          end
          child = section['children'][0]
          if ( section['type'] == 'event_list') &
            (@@relative_timings.member?(section['typecode']) || (section['typecode'] == 'PRCN')) &
            ( child['typecode'] == 'DURING' ) &
            ( (child['type'] == 'date_interval') || (child['type'] == 'date_single'))
            @@errfout.puts "mergeEventListDuringInterval -- section depth = #{section['maxDepth']} title #{section['title']} ph_id = #{section['ph_id']}"
            if child['type'] == 'date_single'
              startdate = enddate = getEmitName(child)
            else
              startdate = "#{getEmitName(child)}.start"
              enddate = "#{getEmitName(child)}.end"    
            end      
            section['status'] = 'emit'
            section['pattern'] = 'eventlistduringinterval'
            section['value'] =  "eventsDuring(#{getEmitName(section)}, #{startdate}, #{enddate})"
            section['name'] = getNodeName(section['value'] )
          end  
        end
      end

      # We are looking for an event list (e.g., activeDiabetes) during an event list
      def self.mergeEventListDuringEventList(section)
        # if we've bottomed out, return
        if section['maxDepth'] == 0
          return
        end
        if section['maxDepth'] > 1
          section['children'].each do |child|
            self.mergeEventListDuringEventList(child)
          end
        else   # depth = 1
          #pattern is typecode PRCN for this node, type event_list
          # single child must be typecode DURING and type event_list
          # translation is n# = EventsDuringEvents(valueParent, valueChild) of type event_list
          if !section['children']
            raise "there should be children and there are none"
          end
          if section['children'].length > 1
            return
          end
          child = section['children'][0]
          if (section['typecode'] == 'PRCN') &
            ( section['type'] == 'event_list') &
            ( child['typecode'] == 'DURING' ) &
            ( child['type'] == 'event_list')
            @@errfout.puts "mergeEventListDuringEventList -- section depth = #{section['maxDepth']} title #{section['title']} ph_id = #{section['ph_id']}"
            section['status'] = 'emit'
            section['pattern'] = 'eventlistduringeventlist'
            section['value'] =  "eventsDuringEvents(#{getEmitName(section)}, #{getEmitName(child)})"
            section['name'] = getNodeName(section['value'] )
          end  
        end
      end

      # We are looking for an event list (e.g., activeDiabetes)  with a child [SBS, SAE, etc]  that has already been emitted
      def self.mergeEventListTimingEventListFlat(section)
        # if we've bottomed out, return
        if section['maxDepth'] < 1
          return
        end
        if section['maxDepth'] > 1
          section['children'].each do |child|
            #          @@errfout.puts "recursing #{child['name']}"
            self.mergeEventListTimingEventListFlat(child)
          end
        else   # depth = 1
          @@errfout.puts "mergeEventListTimingEventListFlat -- section #{section['name']}  typecode #{section['typecode']}"
          #pattern is typecode PRCN for this node, type event_list
          # single child must be typecode SBS/SAE/etc, with a low/high value
          # child node must already have been emitted
          # translation is n# = EventsTimingEvents(nameParent, namechild, timing, low,units,inclusive, high, units,inclusive) of type event_list
          if !section['children']
            raise "there should be children and there are none"
          end
 #         @@errfout.puts "node #{section['name']} has children = #{section['children'].length}"
          if section['children'].length != 1
            return
          end
          timingchild = section['children'][0]
          #        @@errfout.puts "eventlist =#{elchild['name']} timing = #{timingchild['name']} timingchildel = #{timingchildel['name']}  "
          #        @@errfout.puts "typecode = #{section['typecode']} type = #{section['type']} timing = #{timingchild['typecode']} eltype = #{elchild['type']}"
          if ( section['type'] != 'event_list') |
            (!@@relative_timings.member?(timingchild['typecode'])) |
            ( timingchild['type'] != 'event_list') |
            ( timingchild['status'] != 'emitted')
            return
          end
          timinginfo = self.extracttiming(timingchild)
 
          section['status'] = 'emit'
          section['pattern'] = 'eventlisttimingeventlistflat'

          basevalue =  "eventsTimingEvents(#{getEmitName(section)}, #{getEmitName(timingchild)}, #{timinginfo['invert']}, #{timinginfo['typecode']}, #{timinginfo['low']},#{timinginfo['high']}, #{timinginfo['lowunits']}, #{timinginfo['highunits']}, #{timinginfo['lowinclusive']}, #{timinginfo['highinclusive']})"
          if (timinginfo['subs_code'] != "NONE")
            value = "#{timinginfo['subs_code']}( #{basevalue} )"
          else
            value = basevalue
          end
          section['value'] = value
          section['name'] = getNodeName(value)
          section['type'] = 'event_list'

        end
      end


      # We are looking for an event list (e.g., activeDiabetes) [SBS, SAE, etc]  with a child event list (e.g., office encounter)
      # The structure is the event ist and the timing as siblings and an event list hangling off the timing
      def self.mergeEventListTimingEventList(section)
        # if we've bottomed out, return
        if section['maxDepth'] < 2
          return
        end
        if section['maxDepth'] > 2
          section['children'].each do |child|
            #          @@errfout.puts "recursing #{child['name']}"
            self.mergeEventListTimingEventList(child)
          end
        else   # depth = 2
          @@errfout.puts "mergeEventListTimingEventList -- section #{section['name']} depth = #{section['maxDepth']} title #{section['title']} ph_id = #{section['ph_id']}"
          #pattern is typecode PRCN for this node, type event_list
          # single child must be typecode SBS/SAE/etc, with a low/high value
          # single grandchild must be  type event_list
          # translation is n# = EventsTimingEvents(nameParent, namechild, timing, low,units,inclusive, high, units,inclusive) of type event_list
          if !section['children']
            raise "there should be children and there are none"
          end
#          @@errfout.puts "node #{section['name']} has children = #{section['children'].length}"
          if section['children'].length != 2
            return
          end
          timingchild = section['children'][1]
          timingchildel = timingchild['children'][0]
          elchild = section['children'][0]
          #        @@errfout.puts "eventlist =#{elchild['name']} timing = #{timingchild['name']} timingchildel = #{timingchildel['name']}  "
          #        @@errfout.puts "typecode = #{section['typecode']} type = #{section['type']} timing = #{timingchild['typecode']} eltype = #{elchild['type']}"
          if ( elchild['type'] != 'event_list') |
            (!@@relative_timings.member?(timingchild['typecode'])) |
            ( timingchildel['type'] != 'event_list')
            return
          end
          low = high = 0
          lowunits = highunits = "d"
          lowinclusive = highinclusive = "true"
          if(timingchild['high'])
            low = timingchild['high']['value']
            lowunits = timingchild['high']['unit']
            lowinclusive = timingchild['high']['inclusive']
          end        
          if(timingchild['low'])
            low = timingchild['low']['value']
            lowunits = timingchild['low']['unit']
            lowinclusive = timingchild['low']['inclusive']
          end
          if timingchild['inversionInd'] == "*invert*"
            a = getEmitName(timingchildel)
            b = getEmitName(elchild)
          else
            b = getEmitName(timingchildel)
            a = getEmitName(elchild)
          end
          section['status'] = 'emit'
          section['pattern'] = 'eventlisttimingeventlist'
          section['value'] =  "eventsTimingEvents(#{a}, #{b}, #{timingchild['typecode']}, #{low},#{high}, #{lowunits}, #{highunits}, #{lowinclusive}, #{highinclusive})"
          section['name'] = getNodeName(section['value'] )
          section['type'] = 'event_list'

        end
      end

      # We are looking for an event list (e.g., activeDiabetes)  with a sibling  TIMING (DURING, SAE) that has already
      # been reduced to an event list (e.g., office encounter) and emitted
      def self.mergeEventListTimingEventListSibling(section)
        # if we've bottomed out, return
        if section['maxDepth'] < 1
          return
        end
        if section['maxDepth'] > 1
          section['children'].each do |child|
            #          @@errfout.puts "recursing #{child['name']}"
            self.mergeEventListTimingEventListSibling(child)
          end
        else   # depth = 2
          @@errfout.puts "mergeEventListTimingEventListSibling -- section #{section['name']} depth = #{section['maxDepth']} title #{section['title']} ph_id = #{section['ph_id']}"
          #pattern is typecode PRCN for this node,
          # first child node is an event list
          # second child must be typecode SBS/SAE/etc, with a low/high value, and have type event_list
          # translation is n# = EventsTimingEvents(nameChild1, namechild2, timing, low,units,inclusive, high, units,inclusive) of type event_list
          if !section['children']
            raise "there should be children and there are none"
          end
          @@errfout.puts "node #{section['name']} has children = #{section['children'].length}"
          if section['children'].length != 2
            return
          end
          elchild = section['children'][0]
          timingchild = section['children'][1]

          #        @@errfout.puts "eventlist =#{elchild['name']} timing = #{timingchild['name']} timingchildel = #{timingchildel['name']}  "
          #        @@errfout.puts "typecode = #{section['typecode']} type = #{section['type']} timing = #{timingchild['typecode']} eltype = #{elchild['type']}"
          if ( elchild['type'] != 'event_list') |
            (!@@relative_timings.member?(timingchild['typecode'])) |
            ( timingchild['type'] != 'event_list')
            return
          end
          low = high = 0
          lowunits = highunits = "d"
          lowinclusive = highinclusive = "true"
          if(timingchild['high'])
            low = timingchild['high']['value']
            lowunits = timingchild['high']['unit']
            lowinclusive = timingchild['high']['inclusive']
          end        
          if(timingchild['low'])
            low = timingchild['low']['value']
            lowunits = timingchild['low']['unit']
            lowinclusive = timingchild['low']['inclusive']
          end
          if timingchild['inversionInd'] == "*invert*"
            a = getEmitName(timingchild)
            b = getEmitName(elchild)
          else
            b = getEmitName(timingchild)
            a = getEmitName(elchild)
          end
          section['status'] = 'emit'
          section['pattern'] = 'eventlisttimingeventlistsibling'
          section['value'] =  "eventsTimingEvents(#{a}, #{b}, #{timingchild['typecode']}, #{low},#{high}, #{lowunits}, #{highunits}, #{lowinclusive}, #{highinclusive})"
          section['name'] = getNodeName(section['value'] )
          section['type'] = 'event_list'

        end
      end

      # we are looking for a section with max_depth = 1, with multiple children ORed together that are of type event lists
      # the result is to kill off these children, and replace them with a single section type "value", and value of "normalize([child event lists])" 
      # recursion returns number of children that are candidates for merging     
      def self.mergeValueSets(section)
        # if we've bottomed out, return
        num_merges = 0
        if section['maxDepth'] == 0
          #    @@errfout.puts "conj_code = #{section['conj_code']} type = #{section['type']}"
          if (section['conj_code'] == "OR") &
            (section['type'] == "event_list")
            num_merges = 1
          else
            num_merges = 0
          end
        elsif # recurse
          section['children'].each do |child|
            #      @@errfout.puts "#{child['name']}"
            num_merges = num_merges + self.mergeValueSets(child)
          end
          #    @@errfout.puts "num_merges = #{num_merges}"
        end
        section['num_merges'] = num_merges
        if (section['maxDepth'] != 1) | (num_merges == 0)
          #    @@errfout.puts "returning...depth = #{section['maxDepth']} and num_merges = #{num_merges}"
          return num_merges
        end
        self.mergeChildValueSets(section)

        return 0
      end

      def self.mergeChildValueSets(section)
        newchildren = []
        mergelist = []
        nameslist = []
        # iterate over children, and build list of merging children
        section['children'].each do |child|
          if child['num_merges'] == 1
            mergelist << getEmitName(child)
            nameslist << child['name']
          end
        end

        value = "normalize(#{mergelist.join(', ')})"
        oldnames = nameslist.join(',')
        newname = getNodeName(value)
        newnode = {'name' => newname, 'oldnames' => oldnames, 'value' => value, 'type' => "value", 'level' => '0',  'num_merges' => '0', 'type' => "event_list", 'status' => 'emit', 'pattern' =>'merged_value_sets'} 
        newchildren << newnode
        # iterate over children, and build list of merging children
        section['children'].each do |child|
          if child['num_merges'] != 1
            newchildren << child
          end
        end  
        section['children'] = newchildren 
      end

    end


  end

  # if launched as a standalone program, not loaded as a module
  if __FILE__ == $0
    HQMFToCode::GenCodeDirParse.process(ARGV[0],ARGV[1])
  end

