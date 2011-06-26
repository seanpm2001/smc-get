#Encoding: UTF-8

module SmcGet
  
  class LocalRepository < Repository
    
    #Directory where the package specs are kept.
    SPECS_DIR            = Pathname.new("packages")
    #Directory where downloaded packages are cached.
    CACHE_DIR            = Pathname.new("cache")
    #Directory where the packages’ level files are kept.
    CONTRIB_LEVELS_DIR   = Pathname.new("levels") #Levels in subdirectories are currently not recognized by SMC
    #Directory where the packages’ music files are kept.
    CONTRIB_MUSIC_DIR    = Pathname.new("music") + "contrib-music"
    #Directory where the packages’ graphic files are kept.
    CONTRIB_GRAPHICS_DIR = Pathname.new("pixmaps") + "contrib-graphics"
    #Directory where the packages’ sound files are kept.
    CONTRIB_SOUNDS_DIR   = Pathname.new("sounds") + "contrib-sounds"
    #Directory where the packages’ world files are kept
    CONTRIB_WORLDS_DIR   = Pathname.new("world") #Worlds in subdirectores are currently not recognized by SMC
    
    #Root path of the local repository. Should be the same as your SMC’s
    #installation path.
    attr_reader :path
    #This repository’s specs dir.
    attr_reader :specs_dir
    #This repository’s cache dir.
    attr_reader :cache_dir
    #This repository’s package levels dir.
    attr_reader :contrib_level_dir
    #This repository’s package music dir.
    attr_reader :contrib_music_dir
    #This repository’s package graphics dir.
    attr_reader :contrib_graphics_dir
    #This repository’s package sounds dir.
    attr_reader :contrib_sounds_dir
    #This repository’s package worlds dir.
    attr_reader :contrib_worlds_dir
    #An array of PackageSpecification objects containing the specs of
    #all packages installed in this repository.
    attr_reader :package_specs
    
    def initialize(path)
      @path         = Pathname.new(path)
      @specs_dir    = @path + SPECS_DIR
      @cache_dir    = @path + CACHE_DIR
      @levels_dir   = @path + CONTRIB_LEVELS_DIR
      @music_dir    = @path + CONTRIB_MUSIC_DIR
      @graphics_dir = @path + CONTRIB_GRAPHICS_DIR
      @sounds_dir   = @path + CONTRIB_SOUNDS_DIR
      @worlds_dir   = @path + CONTRIB_WORLDS_DIR
      
      #Create the directories if they’re not there yet
      [@specs_dir, @cache_dir, @levels_dir, @music_dir, @graphics_dir, @sounds_dir, @worlds_dir].each do |dir|
        dir.mkpath unless dir.directory?
      end
      
      @package_specs = []
      @specs_dir.children.each do |spec_path|
        next unless spec_path.to_s.end_with?(".yml")
        @package_specs << PackageSpecification.from_file(spec_path)
      end
    end
    
    def fetch_spec(spec_file, directory = ".")
      directory = Pathname.new(directory)
      
      spec_file_path = @specs_dir + spec_file
      raise(Errors::NoSuchResourceError.new(:spec, spec_file), "Package specification '#{spec_file}' not found in the local repository '#{to_s}'!") unless spec_file_path.file?
      
      directory.mktree unless directory.directory?
      
      #No need to really "fetch" the spec--this is a *local* repository.
      FileUtils.cp(spec_file_path, directory)
      directory + spec_file
    end
    
    def fetch_package(pkg_file, directory = ".")
      directory = Pathname.new(directory)
      
      pkg_file_path = @cache_dir + pkg_file
      raise(Errors::NoSuchPackageError.new(pkg_file.sub(/\.smcpak/, "")), "Package file '#{pkg_file}' not found in this repository's cache!") unless pkg_file_path.file?
      
      directory.mktree unless directory.directory?
      
      #No need to really "fetch" the package--this is a *local* repository
      FileUtils.cp(pkg_file_path, directory)
      directory + pkg_file
    end
    
    def install(package, &block)
      path = package.decompress(SmcGet.temp_dir) + package.spec.name
      
      package.spec.save(@specs_dir)
      
      FileUtils.cp_r(path.join(Package::LEVELS_DIR).children, @levels_dir)
      FileUtils.cp_r(path.join(Package::MUSIC_DIR).children, @music_dir)
      FileUtils.cp_r(path.join(Package::GRAPHICS_DIR).children, @graphics_dir)
      FileUtils.cp_r(path.join(Package::SOUNDS_DIR).children, @sounds_dir)
      FileUtils.cp_r(path.join(Package::WORLDS_DIR).children, @worlds_dir)
      
      FileUtils.cp(package.path, @cache_dir)
      
      @package_specs << package.spec #This package is now installed and therefore the spec must be in that array
    end
    
    def uninstall(pkg_name)
      pkg = @packages.find{|pkg| pkg.spec.name == pkg_name}
      
      [:levels, :music, :sounds, :graphics, :worlds].each do |sym|
        contrib_dir = self.class.const_get(:"CONTRIB_#{sym.upcase}_DIR")
        
        #Delete all the files
        files = pkg.spec.send(sym)
        files.each do |filename|
          File.delete(contrib_dir + filename)
        end
        
        #Delete now empty directories
        loop do
          empty_dirs = []
          contrib_dir.find do |path|
            next if path.basename == contrib_dir #We surely don’t want to delete the toplevel dir.
            empty_dirs << path if path.directory? and path.children.empty?
          end
          #If no empty directories are present anymore, break out of the loop.
          break if empty_dirs.empty?
          #Otherwise delete the empty directories and redo the process, because
          #the parent directories could be empty now.
          empty_dirs.each{|path| File.delete(path)}
        end
      end
      
      @package_specs.delete(pkg.spec) #Otherwise we have a stale package in the array
    end
    
    def contain?(pkg)
      if pkg.kind_of? Package
        @package_specs.include?(pkg.spec)
      else
        @package_specs.any?{|spec| spec.name == pkg}
      end
    end
    alias contains? contain?
    
  end
  
end
