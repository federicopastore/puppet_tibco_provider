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
