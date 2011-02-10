#!/usr/bin/env ruby
#Encoding: UTF-8

module SmcGet
  
  #This is the Console User Interface smc-get exposes. Each command
  #is represented by two methods: The <tt>parse_<cmdname>_command</tt> method
  #and the <tt>execute_<cmdname>_command</tt> method. The first one gets
  #the arguments that have been passed on the command-line as an
  #array that it should destructively parse, i.e. after finishing
  #command-line argument parsing, the array should be empty. Have a
  #look at the existing methods to get an idea on how it works. While
  #parsing, you can place information in
  #  @config[:yourcommand]
  #which is a hash you can populate as you wish (but note that the user
  #can specify values for it in the configuration file). You can raise
  #CUI::InvalidCommandline with a message for the user if you detect
  #broken command-line arguments.
  #
  #When CUI#start is invoked, the +execute+ methods are called, and you have
  #access to the @config hash. Again, look at how existing methods deal with
  #this.
  #
  #The last thing one should do when adding a command, is to modify the
  #help message in the HELP_MESSAGE constant to reflect the existance of
  #a new command.
  #
  #Internally the flow is as follows:
  #1. The user calls CUI#initialize with ARGV.
  #2. That method triggers CUI#parse_commandline and passes ARGV to it.
  #3. #parse_commandline analyses the array it receives and calls the
  #   appropriate sub-parsing method. Finally it sets @config[:command] to
  #   the name of the command it found.
  #4. The user calls CUI#start.
  #5. #start looks into @config[:command] and invokes the appropriate
  #   command execution method.
  #6. #start shuts down the interpreter via #exit. If the command execution
  #   method returned an integer value, it is used as the exit status.
  class CUI
    
    #Class for invalid command-line argument errors.
    class InvalidCommandline < Errors::SmcGetError
    end
    
    #Default location of the configuration file.
    DEFAULT_CONFIG_FILE = CONFIG_DIR + "smc-get.yml"
    
    #The help message displayed to the user when issueing "help".
    HELP_MESSAGE =<<EOF
USAGE:
#{$0} [OPTIONS] COMMAND [PARAMETERS...]

DESCRIPTION:
Install and uninstall levels from the Secret Maryo Chronicles contributed level repository.

COMMANDS:
  install\tinstall a package
  uninstall\tuninstall a package
  getinfo\tget information about a package
  help\t\tprint this help message

OPTIONS FOR #$0 ITSELF
  -c FILE\t--config-file FILE\tLoads FILE instead of the default configuration
  \t\t\t\t  file 'config/smc-get.yml'.

PARAMETERS FOR install
  -r\t--reinstall\tForces a reinstallation of the package.

PARAMETERS FOR getinfo
  -r\t--remote\tForces getinfo to do a remote lookup.

The default behaviour is to do a local lookup if the
package is already installed.

Report bugs to: luiji@users.sourceforge.net
smc-get home page: <http://www.secretmaryo.org/>
EOF
    
    #Creates a new CUI. Pass in ARGV or a set of command-line arguments
    #you want to and read this class's documentation for knowing what
    #happens then. Call #start on the returned object when you want
    #to execute everything.
    def initialize(argv)
      @config = {}
      parse_commandline(argv)
      load_config_file
      @smc_get = SmcGet.new(@config[:repo_url], @config[:data_directory])
    end
    
    #Starts executing of the CUI. This method never returns, it
    #calls #exit after the command has finished.
    def start
      begin
        ret = send(:"execute_#{@config[:command]}_command")
        #If numbers are returned they are supposed to be the exit code.
        if ret.kind_of? Integer
          exit ret
        else
          exit
        end
      rescue Errors::SmcGetError => e
        $stderr.puts(e.message) #All SmcGetErrors should have an informative message
        exit 2
      rescue => e #Ouch. Fatal error not intended.
        $stderr.puts("[BUG] #{e.class}")
        $stderr.puts("Please file a bug report at https://github.com/Luiji/smc-get/issues")
        $stderr.puts("and attach this message. Describe what you did so we can")
        $stderr.puts("reproduce it. ")
        raise #Bubble up
      end
    end
    
    private
    
    #Destructively searches through +argv+ (i.e. emptying it) and
    #sets the CLI up. Besides when +help+ is used as the
    #command, nothing is actually executed.
    #
    #This method calls the various parse_*_command methods,
    #where the asterisk * represents a single command. Each
    #command therefore has it's own parsing, making smc-get
    #easily extendable by adding another parse_*_command
    #method (it will automatically be found by this method).
    def parse_commandline(argv)
      
      #Get options for smc-get itself, rather than it's subcommands.
      #First, define the default behaviour:
      @config_file = DEFAULT_CONFIG_FILE
      #Now, check for updates:
      while !argv.empty? and argv.first.start_with?("-") #All options start with a hyphen, commands cannot
        arg = argv.shift
        case arg
        #-c CONFIG | --config-file CONFIG
        when "-c", "--config-file" then @config_file = Pathname.new(argv.shift)
        else
          $stderr.puts("Invalid option #{arg}.")
          $stderr.puts("Try #$0 help.")
          exit 1
        end
      end
      
      #If nothing is left, the command was left out. Assume 'help'.
      argv << "help" if argv.empty?
      
      #Now parse the subcommand.
      command = argv.shift.to_sym
      sym = :"parse_#{command}_command"
      if respond_to?(sym, true) #Private method
        #The @config hash saves all that is parsed from
        #the commandline and the configuration file, in the
        #following format:
        #  {
        #    :command => THE_COMMAND_TO_EXECUTE,
        #    all_toplevel_options_and_values,
        #    :command_name => {
        #      all_args_and_vals_for_this_command
        #    }
        #  }
        #The toplevel options can solely be set through
        #the configuration file, but the arguments for
        #the commands may be set on the command-line or
        #in the config file (the first taking precedence).
        @config[:command] = command
        @config[command] = {}
        begin
          send(sym, argv)
        rescue InvalidCommandline => e
          $stderr.puts(e.message)
          $stderr.puts("Try #$0 help.")
          exit 1
        end
      else
        $stderr.puts "Unrecognized command #{command}. Try 'help'."
        exit 1
      end
    end
    
    def load_config_file
      #Check for existance of the configuration file and use the
      #default if it doesn't exist.
      unless @config_file.file?
        $stderr.puts("Configuration file #@config_file not found.")
        $stderr.puts("Falling back to the default configuration file.")
        @config_file = DEFAULT_CONFIG_FILE
      end
      #Load the config file and turn it's keys to symbols
      hsh = Hash[YAML.load_file(@config_file.to_s).map{|k, v| [k.to_sym, v]}]
      @config.merge!(hsh){|key, old_val, new_val| old_val} #Command-line args overwrite those in the config
    end
    
    def parse_help_command(args)
      raise(InvalidCommandline, "help doesn't take arguments.") unless args.empty?
    end
    
    def parse_install_command(args)
      raise(InvalidCommandline, "No package given.") if args.empty?
      while args.count > 1
        arg = args.shift
        case arg
        when "--reinstall", "-r" then @config[:install][:reinstall] = true
        else
          raise(InvalidCommandline, "Invalid argument #{arg}.")
        end
      end
      #The last command-line arg is the package
      @config[:install][:package] = args.shift
    end
    
    def parse_uninstall_command(args)
      raise(InvalidCommandline, "No package given.") if args.empty?
      while args.count > 1
        arg = args.shift
        #case arg
        #when "-c", "--my-arg" then ...
        #else
          raise(InvalidCommandline, "Invalid argument #{arg}.")
          #end
      end
      #The last command-line arg is the package
      @config[:uninstall][:package] = args.shift
    end
    
    def parse_getinfo_command(args)
      while args.count > 1
        arg = args.shift
        case arg
        when "-r", "--remote" then @config[:getinfo][:force_remote] = true
        else
          raise(InvalidCommandline, "Invalid argument #{arg}.")
        end
      end
      #The last command-line arg is the package
      @config[:getinfo][:package] = args.shift
    end
    
    def execute_help_command
      puts HELP_MESSAGE
    end
    
    def execute_install_command
      pkg = @config[:install][:package]
      if @smc_get.package_installed?(pkg)
        if @config[:install][:reinstall]
          puts "Reinstalling #{pkg}."
        else
          puts "Already installed. Nothing to do, maybe you want --reinstall?."
          return
        end
      end
      puts "Installing #{pkg}."
      #Windows doesn't understand ANSI escape sequences, so we have to
      #use the carriage return and reprint the whole line.
      base_str = "\r[%.2f%%] Downloading %s... (%.2f%%)"
      @smc_get.install(pkg) do |percent_total, filename, percent_filename|
        print "\r", " " * 80 #Clear everything written before
        printf(base_str, percent_total, filename, percent_filename)
      end
      puts
    end
    
    def execute_uninstall_command
      pkg = @config[:uninstall][:package]
      puts "Uninstalling #{pkg}."
      #Windows doesn't understand ANSI escape sequences, so we have to
      #use the carriage return and reprint the whole line.
      base_str = "\r[%.2f%%] Removing %s... (%.2f%%)"
      @smc_get.uninstall(pkg) do |percent_total, part, percent_part|
        print "\r", " " * 80 #Clear everything written before
        printf(base_str, percent_total, part, percent_part)
      end
    end
    
    def execute_getinfo_command
      pkg = @config[:getinfo][:package]
      #Get the information
      info = if @smc_get.package_installed?(pkg)
        if @config[:getinfo][:force_remote]
          @smc_get.getinfo(pkg, true)
        else
          @smc_get.getinfo(pkg)
        end
      else
        @smc_get.getinfo(pkg)
      end
      #Now output the information
      puts "Title: #{info['title']}"
      if info['authors'].count == 1
        puts "Author: #{info['authors'][0]}"
      else
        puts 'Authors:'
        info['authors'].each do |author|
          puts "  - #{author}"
        end
      end
      puts "Difficulty: #{info['difficulty']}"
      puts "Description: #{info['description']}"
    end
    
  end
  
end
