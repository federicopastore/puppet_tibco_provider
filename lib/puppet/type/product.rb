require 'pathname'
require 'uri'

Puppet::Type.newtype(:product) do

  desc 'product type is an example of how to write a Puppet type useful to manage thirdy part products.'

  feature :installable, "The provider can install products.",
        :methods => [:install]
  feature :uninstallable, "The provider can uninstall products.",
        :methods => [:uninstall]
          
  feature :patchable, "The provider can install patch on products.",
        :methods => [:applyPatch]
          
  feature :upgradeable, "The provider can upgrade to the latest version of a
  products.  This feature is used by specifying `latest` as the
          desired value for the products.",
        :methods => [:update]
  
  feature :versionable, "The provider is capable of interrogating the
  products database for installed version(s), and can select
          which out of a set of available versions of a products to
          install if asked."
  
#  feature :install_options, "The provider accepts options to be
#        passed to the installer command."
#      feature :uninstall_options, "The provider accepts options to be
#        passed to the uninstaller command."
        
  ensurable do
    desc <<-EOT
      What state the product should be in. On packaging systems that can
      retrieve new products on their own, you can choose which package to
      retrieve by specifying a version number or `latest` as the ensure
      value. On packaging systems that manage configuration files separately
      from "normal" system files, you can uninstall config files by
      specifying `purged` as the ensure value. This defaults to `installed`.
    EOT

    attr_accessor :latest

    newvalue(:present, :event => :product_installed) do
      provider.install
    end

    newvalue(:absent, :event => :product_removed) do
      provider.uninstall
    end


    # Alias the 'present' value.
    aliasvalue(:product_installed, :present)

    newvalue(:latest, :required_features => :upgradeable) do
      # Because yum always exits with a 0 exit code, there's a retrieve
      # in the "install" method.  So, check the current state now,
      # to compare against later.
      current = self.retrieve
      begin
        provider.update
      rescue => detail
        self.fail Puppet::Error, "Could not update: #{detail}", detail
      end

      if current == :absent
        :product_installed
      else
        :product_changed
      end
    end

    newvalue(:patched, :required_features => :patchable) do
          begin
            self.retrieve
            provider.applyPatch
          rescue => detail
            self.fail Puppet::Error, "Could not apply patch: #{detail}", detail
          end
          
      if self.retrieve == :absent
        :product_installed
      else
        :product_patched
      end
          
    end

#    newvalue(/./, :required_features => :patchable) do
#          begin
#            provider.applyPatch
#          rescue => detail
#            self.fail Puppet::Error, "Could not apply patch: #{detail}", detail
#          end
#          :product_patched
#    end
            
    newvalue(/./, :required_features => :versionable) do
      begin
        provider.install
      rescue => detail
        self.fail Puppet::Error, "Could not update: #{detail}", detail
      end

      if self.retrieve == :absent
        :product_installed
      else
        :product_changed
      end
    end

    defaultto :product_installed

    # Override the parent method, because we've got all kinds of
    # funky definitions of 'in sync'.
    def insync?(is)
      @lateststamp ||= (Time.now.to_i - 1000)
      # Iterate across all of the should values, and see how they
      # turn out.

      @should.each { |should|
        case should
        when :present
          return true unless [:absent].include?(is)
        when :latest
          # Short-circuit packages that are not present
          return false if is == :absent

          # Don't run 'latest' more than about every 5 minutes
          if @latest and ((Time.now.to_i - @lateststamp) / 60) < 5
            #self.debug "Skipping latest check"
          else
            begin
              @latest = provider.latest
              @lateststamp = Time.now.to_i
            rescue => detail
              error = Puppet::Error.new("Could not get latest version: #{detail}")
              error.set_backtrace(detail.backtrace)
              raise error
            end
          end

          case
            when is.is_a?(Array) && is.include?(@latest)
              return true
            when is == @latest
              return true
            when is == :present
              # This will only happen on retarded packaging systems
              # that can't query versions.
              return true
            else
              self.debug "#{@resource.name} #{is.inspect} is installed, latest is #{@latest.inspect}"
          end


        when :absent
          return true if is == :absent
        # this handles version number matches and
        # supports providers that can have multiple versions installed
        when *Array(is)
          return true
        else
          # We have version numbers, and no match. If the provider has
          # additional logic, run it here.
          return provider.insync?(is) if provider.respond_to?(:insync?)
        end
      }

      false
    end

    # This retrieves the current state. LAK: I think this method is unused.
    def retrieve
      provider.properties[:ensure]
    end

    # Provide a bit more information when logging upgrades.
    def should_to_s(newvalue = @should)
      if @latest
        @latest.to_s
      else
        super(newvalue)
      end
    end
  end


  newparam(:name) do
    desc "The product name.
    "
    isnamevar

    validate do |value|
      if !value.is_a?(String)
        raise ArgumentError, "Name must be a String not #{value.class}"
      end
    end
  end

 providify
     # paramclass(:provider).isnamevar 
  
  newparam(:zipped) do
    newvalues(:true, :false)
  end

  newparam(:repository) do

  end
  
  newparam(:alwaysreinstall) do
  end
  
  newparam(:type) do
  end  

  newparam(:error) do
  end  

  newparam(:displayname) do
  end 
       
  newparam(:source) do
    validate do |value|
      unless Pathname.new(value).absolute? ||
        URI.parse(value).is_a?(URI::HTTP)
        fail("Invalid source #{value}")
      end
    end
  end


  newparam(:responsefileproperites) do
        desc "A file containing any necessary answers to questions asked by
          the product.  This is currently used on Solaris and Debian.  The
          value will be validated according to system rules, but it should
          generally be a fully qualified path."
      end  
      
  newparam(:responsefile) do
        desc "A file containing any necessary answers to questions asked by
          the product.  This is currently used on Solaris and Debian.  The
          value will be validated according to system rules, but it should
          generally be a fully qualified path."
      end

  autorequire(:file) do
        autos = []
        [:responsefile].each { |param|
          if val = self[param]
            autos << val
          end
        }
  
        if source = self[:source] and absolute_path?(source)
          autos << source
        end
        autos
      end
  
      # This only exists for testing.
      def clear
        if obj = @parameters[:ensure]
          obj.latest = nil
        end
      end
  
      # The 'query' method returns a hash of info if the package
      # exists and returns nil if it does not.
      def exists?
        @provider.get(:ensure) != :absent
      end
  
      def present?(current_values)
        super && current_values[:ensure] != :purged
      end      
        
  newparam(:install_home) do
    validate do |value|
      unless Pathname.new(value).absolute?
        fail("#{value} is invalid as installation home")
      end
    end
  end

  newproperty(:version) do
    validate do |value|
      fail("Invalid version #{value}") unless value =~ /^[0-9A-Za-z\.-]+$/
    end
  end

newproperty(:type) do
end

newproperty(:id) do
end  

#newproperty(:status) do
#end 
#
#newproperty(:error) do
#end 


  validate do
    fail('source is required when ensure is present') if self[:ensure] == :present and self[:source].nil?
    fail('source cannot be directory when zipped is true') if self[:zipped] == :true and self[:source].nil?
  end


end