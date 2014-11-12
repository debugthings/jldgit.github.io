module Jekyll
  
  class LessCssFile < StaticFile
    def write(dest)
      # do nothing
    end
  end
  
# Expects a lessc: key in your _config.yml file with the path to a local less.js/bin/lessc
# Less.js will require node.js to be installed
  class LessJsGenerator < Generator
    safe true
    priority :low
    
    def generate(site)
      src_root = site.config['source']
      dest_root = site.config['destination']
      less_files = site.config['less_files']
      less_output = site.config['less_output']
      less_ext = /\.less$/i
      
      raise "Missing 'lessc' path in site configuration" if !site.config['lessc']
      
      # static_files have already been filtered against excludes, etc.
      less_files.each do |sf|
        next if not sf =~ less_ext
        less_path = sf
        puts "Less path " + less_path
        less_file = [src_root, less_path].join()
        puts "Less file " + less_file

        css_dir_name = [src_root, less_output].join()
        css_file = File.basename(less_file.gsub(less_ext, '.css'))
        css_outfile = [css_dir_name, css_file].join()
        puts "CSS File " + css_file

        css_dir = File.dirname(css_outfile)
        puts "CSS dir " + css_dir

        FileUtils.mkdir_p(css_dir)

        css_dir_relative = css_dir.gsub(src_root, '')
          puts "CSS dir " + css_dir_relative
 
        begin
          command = [site.config['lessc'], 
                     less_file, 
                     css_outfile
                     ].join(' ')
                     
          puts 'Compiling LESS: ' + command
                     
          `#{command}`
          
          raise "LESS compilation error" if $?.to_i != 0
        end
        
        # Add this output file so it won't be cleaned
        site.static_files << LessCssFile.new(site, site.source, css_dir_relative, css_file)
      end
    end
    
  end
end