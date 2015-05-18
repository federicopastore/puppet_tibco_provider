Facter.add('osplatform') do 
  setcode do
    case Facter.value(:osfamily)
    when 'Windows'
      'win'
    when "Darwin"
      'macosx'
    else
      'linux'
    end
  end
end

Facter.add('TIBCOUniversalInstaller') do 
  setcode do
    case Facter.value(:osfamily)
    when 'Windows'
      'win'
    when "Darwin"
      'TIBCOUniversalInstaller-mac.command'
    else
      'TIBCOUniversalInstaller-lnx-'+Facter.value(:hardwaremodel)+'.bin'
    end
  end
end