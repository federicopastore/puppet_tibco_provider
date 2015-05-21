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
    hwmodel = Facter.value(:hardwaremodel)
    hwmodel.gsub!('_','-')
    case Facter.value(:osfamily)
    when 'Windows'
      'TIBCOUniversalInstaller-win'+hwmodel+'.exe'
    when "Darwin"
      'TIBCOUniversalInstaller-mac.command'
    else
      'TIBCOUniversalInstaller-lnx-'+hwmodel+'.bin'
    end
  end
end