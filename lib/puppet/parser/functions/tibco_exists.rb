begin
        require 'puppet/util/log'
        # restart the puppetmaster when changed
        module Puppet::Parser::Functions
        newfunction(:tibco_exists, :type => :rvalue) do |args|

                tibco = lookup_tibco_var('tibco_home')
                log "tibco_exists #{tibco}"

                if tibco == 'empty' or tibco == 'NotFound'
                        log 'tibco_exists return empty -> false'
                        return false
                else
                        software = args[0].strip
                        log "tibco_exists compare #{tibco} with #{software}"
                        if tibco.include? software
                                log 'tibco_exists return true'
                                return true
                        end
                end
                log 'tibco_exists return false'
                return false

        end

        def lookup_tibco_var(name)
                # puts "lookup fact "+name
                if tibco_var_exists(name)
                        return lookupvar(name).to_s
                end
                'empty'
        end

        def tibco_var_exists(name)
                # puts "lookup fact "+name
                if lookupvar(name) != :undefined
                        if lookupvar(name).nil?
                        # puts "return false"
                                return false
                        end
                return true
                end
                # puts "not found"
                false
        end

        def log(msg)
                Puppet::Util::Log.create(
                :level   => :info,
                :message => msg,
                :source  => 'oracle_exists'
                )
        end
end
end