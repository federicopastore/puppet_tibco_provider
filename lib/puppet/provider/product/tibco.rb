require 'puppet/provider/productprovider'
#require 'puppet/productprovider'
require 'puppet/type/product'
#require 'puppet/util/package'
require 'puppet'
require 'nokogiri'
#require 'rexml/document'
#require 'facter'



Puppet::Type.type(:product).provide(:tibco, :parent => Puppet::Provider::ProductProvider) do

  #TODO enable Purge management to align instances to puppet catalog!!!
  
  desc "Tibco package management for puppet"

  has_feature :versionable, :patchable


  confine :operatingsystem => [:debian, :ubuntu, :centos, :darwin]
 
   def self.get_install_location(resource)
     #notice("called get_install_location ")
     install_location = resource[:zipped] == :false ? resource[:source] : "/tmp/#{resource[:name]}"
     return install_location
   end

   def self.unzip(resource)
     #notice("called unzip ")
     command = ["unzip", resource[:source], "-d /tmp/#{resource[:name]}"].flatten.compact.join(' ')
     output = execute(command, :failonfail => false, :combine => true)
   end
   
   def self.find_installer(resource)
     #notice("called find_installer ")
     installer_dir = resource[:ensure] == :absent || resource[:ensure] == :patched ? resource[:install_home]+"/tools/universal_installer" : get_install_location(resource)
     installer = "unset"
     if File.directory?(installer_dir)
             begin
               execpipe(["ls", installer_dir + "/TIBCOUniversalInstaller*.bin"]) do |process|
                 process.each_line do |line|
                   line.chomp!
                   if line.empty? ; next; end
                   installer = line
                 end
               end
             rescue Puppet::ExecutionFailure
               return installer
             end
         end
       
     return installer
   end
 
   
  def self.get_hash_for_query(path)
    #notice("called get_hash_for_query ")
    options = Hash.new
    if File.directory?(path+"/_installInfo")
        begin#FIXME repair ls command in installInfo exists but have no xml files
          execpipe(["ls", path + "/_installInfo/*.xml"]) do |process|
            process.each_line do |line|
              line.chomp!
              if line.empty? ; next; end
              option = build_product(line)
              options[option[:name]] = option
              #notice("option: #{options[option[:name]]}")
            end
          end
        rescue Puppet::ExecutionFailure
          return options
        end
    end
    return options
  end
   
      
  def self.get_tibco_products(path)
    #notice("called get_tibco_products ")
    products = Hash.new
    if File.directory?(path+"/_installInfo")
        begin
          execpipe(["ls", path + "/_installInfo/*.xml"]) do |process|
            process.each_line do |line|
              line.chomp!
              if line.empty? ; next; end
              options = build_product(line)
              products[options[:name]] = new(options)
              #notice("product: #{products[options[:name]]}")
            end
          end
        rescue Puppet::ExecutionFailure
          #notice("error in get_tibco_products")
          return products
        end
    end
    return products
  end
  
  def self.build_product(line)
    #notice("called build_product ")
    doc = Nokogiri::XML(File.open(line))
    productName = doc.xpath('/TIBCOInstallerFeatures/productDef/@name')
    productVersion = doc.xpath('/TIBCOInstallerFeatures/productDef/@version')
    productType = doc.xpath('/TIBCOInstallerFeatures/productDef/@productType')
    productId = doc.xpath('/TIBCOInstallerFeatures/productDef/@id')
    reinstall = doc.xpath('/TIBCOInstallerFeatures/productDef/@alwaysReinstall')
    #notice("after parsing: productName= #{productName}, productVersion=#{productVersion}, productType=#{productType}, productId=#{productId}, reinstall=#{reinstall}")
    return {:name => productId.to_s, :displayname => productName.to_s, :type => productType.to_s, :provider => name, :ensure => productVersion.to_s, :status => :installed, :alwaysreinstall => reinstall.to_s, :error => 'ok'}
  end
  


  def self.createResponseFile(resource)
    #notice("called createResponseFile ")
    responsefileproperites = resource[:responsefileproperites]
    builder = Nokogiri::XML::Builder.new do |xml|
      xml.doc.create_internal_subset(
          'properties',
          "SYSTEM",
          "http://java.sun.com/dtd/properties.dtd"
        )
        xml.properties do
          responsefileproperites.keys.each do |key|
            xml.entry(responsefileproperites[key], "key" => key)
            end
        end
      filename = resource[:ensure] == :absent ? resource[:install_home]+"/tools/universal_installer/puppet.silent" : get_install_location(resource)+"/puppet.silent"
      f = File.open(filename, "w")
      f.write(xml.to_xml)
      f.close
    end
  end

  def self.prefetch(products)
    notice("called prefetch ")
    prod = products.values[0]
    install_home = prod.value(:install_home)
    products_installed = get_tibco_products(install_home)
    products.keys.each do |name|
        if provider = products_installed[ name ]
          products[name].provider = provider
        end
    end
  end
  
  def self.buildResource(resource)
    location = resource[:ensure] ==:patched ? resource[:repository] + "/HOTFIXES" :resource[:repository]+ "/PRODUCTS"
    location +="/#{resource[:name]}/#{resource[:ensure]}/TIB_#{resource[:name]}_#{resource[:ensure]}-HF-*.zip"
    #notice("location : #{location}")
    return location
  end

  def applyPatch
    notice("called applyPatch for version #{@property_hash[:version]}")
    #first try to install if not present
    #install
    
    resourceItem = self.class.buildResource(@resource)
    notice("resourceItem Found: #{resourceItem}")

  end
  

  def query
    notice("called query for #{@resource[:name]}")
    hash = nil
    begin
      products = self.class.get_hash_for_query(@resource[:install_home])
      #notice("product queried: #{products[@resource[:name]]}")
      hash = products[@resource[:name]]
      #notice("hash: #{hash}")
    rescue Puppet::ExecutionFailure
      #notice("query error")
       return {:ensure => :absent, :status => 'missing', :name => @resource[:name], :error => 'ok'}
    end

    hash ||= {:ensure => :absent, :status => 'missing', :name => @resource[:name], :error => 'ok'}

    if hash[:error] != "ok"
      raise Puppet::Error.new(
        "Product #{hash[:name]}, version #{hash[:ensure]} is in error state: #{hash[:error]}"
      )
    end
    notice("query hash created: #{hash}")
    return hash
  end
  
  def exists?
   #notice("called exists for product #{@resource[:name]}")
   @property_hash[:ensure] == :present
  end

  def install
    #notice("called install for product #{resource}")
    self.class.unzip(@resource)
    self.class.createResponseFile(@resource)
    command = [self.class.find_installer(@resource), "-silent", "-V responseFile='#{self.class.get_install_location(resource)}/puppet.silent'"].flatten.compact.join(' ')
    output = execute(command, :failonfail => false, :combine => true)
  end

  def uninstall
    #notice("called uninstall for product #{@resource[:name]}")
    self.class.createResponseFile(@resource)
    command = [self.class.find_installer(@resource),"-V uninstallProductID='#{@resource[:name]}'","-V uninstallTIBCOHome='#{@resource[:install_home]}'", "-silent", "-V responseFile='#{@resource[:install_home]}/tools/universal_installer/puppet.silent'"].flatten.compact.join(' ')
    output = execute(command, :failonfail => false, :combine => true)
  end

  def update
    #notice("called update for product #{@resource[:name]}")
    install
  end
  
def latest
  notice("called latest")
end

  def version(value)
    #notice("called version for #{value} of product #{@resource[:name]}")
    @property_hash[:version]
  end

# (Un)install may "fail" because the package requested a reboot, the system requested a
# reboot, or something else entirely. Reboot requests mean the package was installed
# successfully, but we warn since we don't have a good reboot strategy.
def check_result(hr)
  operation = resource[:ensure] == :absent ? 'uninstall' : 'install'

  case hr
  when self.class::ERROR_SUCCESS
    # yeah
  when self.class::ERROR_SUCCESS_REBOOT_INITIATED
    warning("The package #{operation}ed successfully and the system is rebooting now.")
  when self.class::ERROR_SUCCESS_REBOOT_REQUIRED
    warning("The package #{operation}ed successfully, but the system must be rebooted.")
  else
    #raise Puppet::Util::Windows::Error.new("Failed to #{operation}", hr)
  end
end

end
  