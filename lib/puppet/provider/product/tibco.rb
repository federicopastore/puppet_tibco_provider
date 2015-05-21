require 'puppet/provider/productprovider'
require 'puppet/type/product'
require 'puppet'
require 'nokogiri'
require 'facter'
require 'versionomy'


Puppet::Type.type(:product).provide(:tibco, :parent => Puppet::Provider::ProductProvider) do

  #TODO enable Purge management to align instances to puppet catalog!!!
  
  desc "Tibco package management for puppet"

  has_feature :versionable

  confine :operatingsystem => [:debian, :ubuntu, :centos]
 
   def self.get_install_location(resource)
     #debug("called get_install_location ")
     install_location = "/tmp/#{resource[:name]}"
     return install_location
   end

   def self.retrieveProductFromRepo(resource)
     source =''
     debug("retrieveProductFromRepo: started")
     arch = Facter.value('hardwaremodel')
     arch.gsub!('_','-')
     debug(arch)
     os = Facter.value('osplatform')
     debug(os)
     case resource[:ensure].to_s
       when 'present'|| 'absent'
         
       else
         if resource[:source].nil?
                         source =resource[:repository]+'/'+resource[:name]+'/'+resource[:ensure]+'/TIB_'+resource[:name]+'_'+resource[:ensure]+'_'+os+'_'+arch+'.zip'
         else
            source = resource[:source]
         end
     end
#     if resource[:ensure] != 'present' || resource[:ensure] != 'absent'
#       if resource[:source].nil?
#         source =resource[:repository]+'/'+resource[:name]+'/'+resource[:ensure]+'/TIB_'+resource[:name]+'_'+resource[:ensure]+'_'+os+'_'+arch+'.zip'
#       else
#       source = resource[:source]
#       end
#     end
     debug("retrieveProductFromRepo: "+source)
     return source
   end
   
   def self.unzip(resource)
     debug("called unzip ")
     command = ["unzip", retrieveProductFromRepo(resource), "-d /tmp/#{resource[:name]}"].flatten.compact.join(' ')
     output = execute(command, :failonfail => false, :combine => true)
   end
   
  def self.copyInstallerToTemp(installer, resource)
    debug("called copyInstallerToTemp "+ installer)
    command = ["cp", installer, "/tmp/#{resource[:name]}/"].flatten.compact.join(' ')
         output = execute(command, :failonfail => false, :combine => true)
    debug("exit copyInstallerToTemp ")
  end
   
  def self.get_InstallerVersion(resource)
    debug("called get_InstallerVersion ")
    inst_version ="---"
    if File.directory?("/tmp/#{resource[:name]}")
        begin
          execpipe(["ls", "/tmp/#{resource[:name]}/product_#{resource[:name]}_*.xml"]) do |process|
            process.each_line do |line|
              line.chomp!
              if line.empty? ; next; end
             # if line.start_with?("product_#{resource[:name]}_")
                  infos = build_product(line)
                  inst_version = infos[:universalinstallerrelease]
                  debug(" get_InstallerVersion exit")
             # end
            end
          end
        rescue Puppet::ExecutionFailure
          return inst_version
        end
    end
    return inst_version
  end
  

  
   def self.find_installer(resource)
     debug("called find_installer ")
     installer_dir = resource[:ensure] == :absent || resource[:ensure] == :patched ? resource[:install_home]+"/tools/universal_installer" : resource[:repository]+"/UniversalInstaller/"+get_InstallerVersion(resource)
     installer = "unset"
     debug("called find_installer wwwwwwwwwww ")
     if File.directory?(installer_dir)
       installer = installer_dir +"/"+Facter.value('TIBCOUniversalInstaller')
#             begin
#               execpipe(["ls", installer_dir + "/TIBCOUniversalInstaller*.bin"]) do |process|
#                 process.each_line do |line|
#                   line.chomp!
#                   if line.empty? ; next; end
#                   installer = line
#                 end
#               end
#             rescue Puppet::ExecutionFailure
#               return installer
#             end
         end
       
     return installer
   end
 
  def self.get_hash_for_query(path)
    debug("called get_hash_for_query ")
    options = Hash.new
    if File.directory?(path+"/_installInfo")
        begin#FIXME repair ls command in installInfo exists but have no xml files
          execpipe(["ls", path + "/_installInfo/*.xml"]) do |process|
            process.each_line do |line|
              line.chomp!
              if line.empty? ; next; end
              option = build_product(line)
              options[option[:name]] = option
              #debug("option: #{options[option[:name]]}")
            end
          end
        rescue Puppet::ExecutionFailure
          return options
        end
    end
    return options
  end
     
  def self.get_tibco_products(path)
    debug("called get_tibco_products ")
    products = Hash.new
    if File.directory?(path+"/_installInfo")
        begin
          execpipe(["ls", path + "/_installInfo/*.xml"]) do |process|
            process.each_line do |line|
              line.chomp!
              if line.empty? ; next; end
              options = build_product(line)
              products[options[:name]] = new(options)
              #debug("product: #{products[options[:name]]}")
            end
          end
        rescue Puppet::ExecutionFailure
          #debug("error in get_tibco_products")
          return products
        end
    end
    return products
  end
  
  def self.build_product(line)
    debug("called build_product "+line)
    doc = Nokogiri::XML(File.open(line))
    productName = doc.xpath('/TIBCOInstallerFeatures/productDef/@name')
    productVersion = doc.xpath('/TIBCOInstallerFeatures/productDef/@version')
    #productType = doc.xpath('/TIBCOInstallerFeatures/productDef/@productType')
    productId = doc.xpath('/TIBCOInstallerFeatures/productDef/@id')
    #reinstall = doc.xpath('/TIBCOInstallerFeatures/productDef/@alwaysReinstall')
    universalinstallerrelease = doc.xpath('/TIBCOInstallerFeatures/productDef/@universalinstallerrelease')
    # Parse version numbers, including common prerelease syntax
    v = Versionomy.parse(productVersion.to_s)
    v.major                                 # => 1
    v.minor                                 # => 4
    v.tiny                                  # => 0
    v.patchlevel                            # => 0
    
    debug("after parsing: productName= #{productName}, productVersion=#{v.major}.#{v.minor}.#{v.tiny}, patchLevel=#{v.patchlevel}, productId=#{productId}, universalinstallerrelease=#{universalinstallerrelease}")
    return {:name => productId.to_s, :displayname => productName.to_s,  :provider => name, :ensure => "#{v.major}.#{v.minor}.#{v.tiny}",:patchlevel => v.patchlevel, :status => :installed, :error => 'ok', :universalinstallerrelease => universalinstallerrelease.to_s}
  end
  
  def self.createResponseFile(resource)
    #debug("called createResponseFile ")
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
    debug("called prefetch ")
    prod = products.values[0]
    install_home = prod.value(:install_home)
    products_installed = get_tibco_products(install_home)
    products.keys.each do |name|
        if provider = products_installed[ name ]
          products[name].provider = provider
        end
    end
  end
  
  def query
    debug("called query for #{@resource[:name]}")
    hash = nil
    begin
      products = self.class.get_hash_for_query(@resource[:install_home])
      #debug("product queried: #{products[@resource[:name]]}")
      hash = products[@resource[:name]]
      #debug("hash: #{hash}")
    rescue Puppet::ExecutionFailure
      #debug("query error")
       return {:ensure => :absent, :status => 'missing', :name => @resource[:name], :error => 'ok'}
    end
    hash ||= {:ensure => :absent, :status => 'missing', :name => @resource[:name], :error => 'ok'}
    if hash[:error] != "ok"
      raise Puppet::Error.new(
        "Product #{hash[:name]}, version #{hash[:ensure]} is in error state: #{hash[:error]}"
      )
    end
    debug("query hash created: #{hash}")
    return hash
  end
  
  def exists?
   debug("called exists for product #{@resource[:name]}")
   @property_hash[:ensure] == :present
  end

  def install
    debug("called install for product #{resource}")
    installer = self.class.find_installer(@resource)
    self.class.unzip(@resource)
    self.class.createResponseFile(@resource)
    self.class.copyInstallerToTemp(installer, @resource)
    command = ["cd /tmp/#{@resource[:name]}/ && chmod +x "+Facter.value('TIBCOUniversalInstaller')+" && ./"+Facter.value('TIBCOUniversalInstaller'), "-silent", "-V responseFile='#{self.class.get_install_location(resource)}/puppet.silent'"].flatten.compact.join(' ')
    output = execute(command, :failonfail => false, :combine => true)
  end

  def uninstall
    #debug("called uninstall for product #{@resource[:name]}")
    self.class.createResponseFile(@resource)
    command = [self.class.find_installer(@resource),"-V uninstallProductID='#{@resource[:name]}'","-V uninstallTIBCOHome='#{@resource[:install_home]}'", "-silent", "-V responseFile='#{@resource[:install_home]}/tools/universal_installer/puppet.silent'"].flatten.compact.join(' ')
    output = execute(command, :failonfail => false, :combine => true)
  end

  def update
    debug("called update for product #{@resource[:name]}")
    install
  end
  
  def latest
    debug("called latest")
  end

  def version(value)
    debug("called version for #{value} of product #{@resource[:name]}")
    @property_hash[:version]
  end


end
  