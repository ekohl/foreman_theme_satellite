require 'fileutils'
require 'net/http'
require 'yaml'
FOREMAN_BRAND = {"Foreman"       => "Satellite", "foreman" => "satellite", "smart-proxy" => "capsule", "Smart-proxy" => "Capsule", "smart proxies" => "capsules", "Smart proxies" => "Capsules",
              "smart-proxies" => "capsules", "Smart-proxies" => "Capsules", "Smart Proxies" => "capsules", "Smart Proxy" => "Capsule", "smart proxy" => "Capsule", "Smart-Proxies" => "capsules",
              "Smart proxy"   => "Capsule", "Compute Profile" => "VM Attributes", "Compute profile" => "VM Attributes", "compute profile" => "VM Attributes", "oVirt" => "RHEV", "ovirt" => "RHEV", "Ovirt" => "RHEV",
              "FreeIPA"       => "Red Hat Identity Management", "OpenStack" => "RHEL OpenStack Platform", "openstack" => "RHEL OpenStack Platform",
              "Openstack"     => "RHEL OpenStack Platform", "Proxy" => "Capsule", "proxy" => "Capsule", "Proxies" => "Capsules", "proxies" => "Capsules"}

def get_dir_path
  tmp = Rails.application.root.to_s.split('/')
  tmp.pop
  tmp.join("/") + "/"
end

DIR_PATH = get_dir_path


def create_reverse_dictionary
  satellite_brand = {"Satellite 6" => ["Foreman"], "satellite 6" => ["foreman"]}
  FOREMAN_BRAND.each do |key, value|
    satellite_brand[value].nil? ? satellite_brand[value] = [key] : satellite_brand[value] << key
  end
  satellite_brand
end

SATELLITE_BRAND = create_reverse_dictionary

def compare_files(files_paths)
  files_paths.each do |file_path|
    tmp_arr = file_path.split('/')
    tmp_arr.pop
    tmp_arr << "/old.po"
    path_to_old = tmp_arr.join('/')
    if File.exists? path_to_old
      path_to_new            = file_path
      new_translations_array = GetPomo::PoFile.parse(File.read(path_to_new), :parse_obsoletes => true)
      old_dictionary         = {}
      old_translations_array = GetPomo::PoFile.parse(File.read(path_to_old), :parse_obsoletes => true)
      old_translations_array.each do |cell|
        old_dictionary[cell.msgid] = cell.msgstr
      end
      new_translations_array.each do |translation|
        translation.msgstr = old_dictionary[translation.msgid] if old_dictionary[translation.msgid] && !old_dictionary[translation.msgid].empty? && !translation.msgid.empty?
      end
      File.open(path_to_new, 'w') { |f|
        f.write(GetPomo::PoFile.to_text(new_translations_array))
      }
      File.delete(path_to_old)
    end
  end
end

def create_prev_version_po_files(files_paths, plugin_name, conf_file)
  files_paths.each do |file_path|
    tmp_arr = file_path.split('/')
    tmp_arr.pop
    lang = tmp_arr.last
    file = get_file_from_gitlab(plugin_name, conf_file[:previous_version], lang)
    create_tmp_file(file.body.to_s, tmp_arr.join('/')) if file.code.include? "200"
  end
end

def validate_en_locale_exist(file)
  plugin_list = []
  file[:plugins].each do |plugin_name, val|
    val = DIR_PATH + plugin_name
    plugin_list << plugin_name unless File.exist?(val + "/locale/en/" + plugin_name + ".po")

  end
  plugin_list.each do |plugin_name|
    puts("***" + plugin_name + " plugin doesn't have a valid locale, please run `rake plugin:gettext['"+plugin_name+"']` from the foreman dir, if possible create a pr against upstream.")
  end
  raise StandardError.new("Please make sure all plugins have valid locale.") unless plugin_list.empty?
end

def get_file_from_gitlab(plugin_name, version, lang)
  url              = "https://gitlab.sat.lab.tlv.redhat.com/satellite6/"+ plugin_name.to_s + "/raw/" + version.to_s + "/locale/" + lang.to_s + "/" + plugin_name.to_s + ".po"
  uri              = URI.parse(url)
  http             = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl     = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  @data            = http.get(uri.request_uri)
  @data.body.force_encoding('UTF-8')
  @data
end

def is_reverse_dictionary?(dictionary)
  dictionary.first[1].is_a? Array
end

def try_to_find_replacement(msg, english_dictionary, replacing_msgstr)
  replace_words = check_sentence(msg, SATELLITE_BRAND)
  # return the sentence if it doesnt have satellite_branded words in it
  return msg unless replace_words
  optional_sentences = switch_words(msg, SATELLITE_BRAND, replace_words)

  # msgstr replacement, it won't matter what sentence we return because all of them are valid options
  return optional_sentences[0] if replacing_msgstr && !optional_sentences.empty?

  optional_sentences.each do |sentence|
    # msgid replacement, valid only if it exist in the en.po
    return sentence if english_dictionary[sentence]
  end
  nil
end

def remove_repeats(words_arr)
  words_arr.each do |word|
    words_arr.delete(word)
    words_arr.unshift(word) if !words_arr.any? { |cell| cell.include? word }
  end
  words_arr
end

def switch_words(sentence, dictionary, words)
  to_copy = sentence
  if words && !sentence.include?("http")
    words = remove_repeats(words)
    words.each_with_index do |replace, replacement_index|
      #case of regular switch process, one option(foreman_brand)
      unless is_reverse_dictionary?(dictionary)
        to_copy = to_copy.gsub(replace, dictionary[words[replacement_index]])
      #case of reverse switch process, multiple options(satellite_brand)
      else
        to_copy = []
        dictionary[words[replacement_index]].each_with_index do |value, value_index|
          to_copy << sentence.gsub(replace, dictionary[words[replacement_index]][value_index])
        end
      end
    end
  end
  # in case the sentence has repeats we remove in `remove_repeats`, e.g "the smart proxy can't proxy requests"
  if !is_reverse_dictionary?(dictionary) && !sentence.include?("http")
    replace_words = check_sentence(to_copy, dictionary)
    to_copy = switch_words(to_copy, dictionary, replace_words) if replace_words && !replace_words.any? { |w| w.downcase.include?("openstack")}
  end
  to_copy
end

def check_sentence(sentence, dictionary)
  temp_arr = []
  dictionary.each do |key, val|
    if sentence.include? key
      temp_arr << key
    end
  end
  return nil if temp_arr.empty?
  temp_arr
end

def get_po_files_path(path, matcher = "po")
  files_paths = Dir[path + "locale/**/*"]
  files_paths.select! do |path|
    path.match(/.*.#{matcher}\z/) && !path.match(/.*\/en\/.*/)
  end
  files_paths
end

def create_english_dictionary(file_path)
  translations_array = GetPomo::PoFile.parse(File.read(file_path), :parse_obsoletes => true)
  translations_array.each do |translation|
    replace_words = check_sentence(translation.msgid, FOREMAN_BRAND)
    translation.msgstr = switch_words(translation.msgid, FOREMAN_BRAND, replace_words) if replace_words && !translation.msgid.empty? && translation.msgstr.empty?
  end
  File.open(file_path, 'w') { |f|
    f.write(GetPomo::PoFile.to_text(translations_array))
  }
end

def create_tmp_file(text, path)
  File.open(path + "/old.po", 'w') { |f|
    f.write(text)
  }
end

# This function takes a plugin locale files and change them to use upstream branded strings
def upstreamize_po(path, plugin_name, replace_msgid)
  files_paths             = get_po_files_path(Pathname.new(path), "old.po")
  english_dictionary           = {}
  english_translations_array = GetPomo::PoFile.parse(File.read(path + '/locale/en/' + plugin_name + '.po'), :parse_obsoletes => true)
  english_translations_array.each do |cell|
    english_dictionary[cell.msgid] = cell.msgstr
  end
  files_paths.each do |file_path|
    translations_array = GetPomo::PoFile.parse(File.read(file_path), :parse_obsoletes => true)
    translations_array.each do |translation|
      translation.msgid  = try_to_find_replacement(translation.msgid, english_dictionary, false) if !translation.msgid.nil? && replace_msgid
      translation.msgstr = try_to_find_replacement(translation.msgstr, english_dictionary, true) unless translation.msgstr.nil?
      translations_array.delete translation if translation.msgid.nil?
    end
    File.open(file_path, 'w') { |f|
      f.write(GetPomo::PoFile.to_text(translations_array))
    }
  end
end

# This function checks the previous version locale files against the upstream locale files
task :match_po => :environment do
  plugin_config_file = YAML.load_file(Pathname.new(DIR_PATH + "foreman_theme_satellite/lib/plugins.yml"))
  validate_en_locale_exist(plugin_config_file)
  plugin_config_file[:plugins].each do |plugin_name, val|
    puts("*Started match process for " + plugin_name)
    val = DIR_PATH + plugin_name if val.empty?
    files_paths = get_po_files_path(Pathname.new(val))

    # create prev version po files
    create_prev_version_po_files(files_paths, plugin_name, plugin_config_file)

    # make po files mergeable with upstream po files
    # check for a 6.1 version is made because only in 6.1 we will have different msgid's, following version will have the same msgid as upstream
    if plugin_config_file[:previous_version].include? "SATELLITE-6.1.0"
      upstreamize_po(val, plugin_name, true)
    else
      upstreamize_po(val, plugin_name, false)
    end

    # match prev version po files with current ones
    compare_files(files_paths)
    puts("*Ended match process for " + plugin_name)
  end
end

# This function changes the msgstr section to use satellite branded strings.
task :after_translation => :environment do
  plugin_config_file = YAML.load_file(Pathname.new(DIR_PATH + "foreman_theme_satellite/lib/plugins.yml"))
  validate_en_locale_exist(plugin_config_file)
  plugin_config_file[:plugins].each do |plugin_name, val|
    puts("*Started modifing " + plugin_name)
    val = DIR_PATH + plugin_name if val.empty?
    create_english_dictionary(val + "/locale/en/" + plugin_name + ".po")
    files_paths = get_po_files_path(Pathname.new(val))
    create_english_dictionary(val + "/locale/en_GB/" + plugin_name + ".po") if files_paths.include?(val + "/locale/en_GB/" + plugin_name + ".po")
    files_paths.each do |file_path|
      translations_array = GetPomo::PoFile.parse(File.read(file_path), :parse_obsoletes => true)
      translations_array.each do |translation|
        replace_words = check_sentence(translation.msgstr, FOREMAN_BRAND)
        translation.msgstr = switch_words(translation.msgstr, FOREMAN_BRAND, replace_words)
      end
      File.open(file_path, 'w') { |f|
        f.write(GetPomo::PoFile.to_text(translations_array))
      }
    end
    puts("*Finished modifing " + plugin_name)
  end
end
