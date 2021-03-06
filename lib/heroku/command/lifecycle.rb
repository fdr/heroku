require "heroku/command/base"

# create, destroy, manage apps
#
class Heroku::Command::Lifecycle < Heroku::Command::Base

  # list
  #
  # list your apps
  #
  def list
    list = heroku.list
    if list.size > 0
      display list.map {|name, owner|
        if heroku.user == owner
          name
        else
          "#{name.ljust(25)} #{owner}"
        end
      }.join("\n")
    else
      display "You have no apps."
    end
  end

  # info
  #
  # show detailed app information
  #
  # -r, --raw  # output info as raw key/value pairs
  #
  def info
    name = (args.first && !args.first =~ /^\-\-/) ? args.first : extract_app
    attrs = heroku.info(name)

    attrs[:web_url] ||= "http://#{attrs[:name]}.#{heroku.host}/"
    attrs[:git_url] ||= "git@#{heroku.host}:#{attrs[:name]}.git"

    if options[:raw] then
      attrs.keys.sort_by(&:to_s).each do |key|
        case key
        when :addons then
          display "addons=#{attrs[:addons].map { |a| a["name"] }.sort.join(",")}"
        when :collaborators then
          display "collaborators=#{attrs[:collaborators].map { |c| c[:email] }.sort.join(",")}"
        else
          display "#{key}=#{attrs[key]}"
        end
      end
    else
      display "=== #{attrs[:name]}"
      display "Web URL:        #{attrs[:web_url]}"
      display "Domain name:    http://#{attrs[:domain_name]}/" if attrs[:domain_name]
      display "Git Repo:       #{attrs[:git_url]}"
      display "Dynos:          #{attrs[:dynos]}"
      display "Workers:        #{attrs[:workers]}"
      display "Repo size:      #{format_bytes(attrs[:repo_size])}" if attrs[:repo_size]
      display "Slug size:      #{format_bytes(attrs[:slug_size])}" if attrs[:slug_size]
      display "Stack:          #{attrs[:stack]}" if attrs[:stack]
      if attrs[:database_size]
        data = format_bytes(attrs[:database_size])
        if tables = attrs[:database_tables]
          data = data.gsub('(empty)', '0K') + " in #{quantify("table", tables)}"
        end
        display "Data size:      #{data}"
      end

      if attrs[:cron_next_run]
        display "Next cron:      #{format_date(attrs[:cron_next_run])} (scheduled)"
      end
      if attrs[:cron_finished_at]
        display "Last cron:      #{format_date(attrs[:cron_finished_at])} (finished)"
      end

      unless attrs[:addons].empty?
        display "Addons:         " + attrs[:addons].map { |a| a['description'] }.join(', ')
      end

      display "Owner:          #{attrs[:owner]}"
      collaborators = attrs[:collaborators].delete_if { |c| c[:email] == attrs[:owner] }
      unless collaborators.empty?
        first = true
        lead = "Collaborators:"
        attrs[:collaborators].each do |collaborator|
          display "#{first ? lead : ' ' * lead.length}  #{collaborator[:email]}"
          first = false
        end
      end

      if attrs[:create_status] != "complete"
        display "Create Status:  #{attrs[:create_status]}"
      end
    end
  end

  # create [NAME]
  #
  # create a new app
  #
  # -r, --remote REMOTE # the git remote to create, default "heroku"
  # -s, --stack  STACK  # the stack on which to create the app
  #
  def create
    remote  = extract_option('--remote', 'heroku')
    stack   = extract_option('--stack', 'aspen-mri-1.8.6')
    timeout = extract_option('--timeout', 30).to_i
    addons  = (extract_option('--addons', '') || '').split(',')
    name    = args.shift.downcase.strip rescue nil
    name    = heroku.create_request(name, {:stack => stack})
    display("Creating #{name}...", false)
    info    = heroku.info(name)
    begin
      Timeout::timeout(timeout) do
        loop do
          break if heroku.create_complete?(name)
          display(".", false)
          sleep 1
        end
      end
      display " done"

      addons.each do |addon|
        display "Adding #{addon} to #{name}... "
        heroku.install_addon(name, addon)
      end

      display [ info[:web_url], info[:git_url] ].join(" | ")
    rescue Timeout::Error
      display "Timed Out! Check heroku info for status updates."
    end

    create_git_remote(name, remote || "heroku")
  end

  # rename NEWNAME
  #
  # rename the app
  #
  def rename
    name    = extract_app
    newname = args.shift.downcase.strip rescue ''
    raise(CommandFailed, "Invalid name.") if newname == ''

    heroku.update(name, :name => newname)

    info = heroku.info(newname)
    display [ info[:web_url], info[:git_url] ].join(" | ")

    if remotes = git_remotes(Dir.pwd)
      remotes.each do |remote_name, remote_app|
        next if remote_app != name
        if has_git?
          git "remote rm #{remote_name}"
          git "remote add #{remote_name} git@#{heroku.host}:#{newname}.git"
          display "Git remote #{remote_name} updated"
        end
      end
    else
      display "Don't forget to update your Git remotes on any local checkouts."
    end
  end


  # open
  #
  # open the app in a web browser
  #
  def open
    app = heroku.info(extract_app)
    url = app[:web_url]
    display "Opening #{url}"
    Launchy.open url
  end

  # destroy
  #
  # permanently destroy an app
  #
  def destroy
    app = extract_app
    info = heroku.info(app)
    url  = info[:domain_name] || "http://#{info[:name]}.#{heroku.host}/"

    if confirm_command(app)
      redisplay "Destroying #{app} (including all add-ons)... "
      heroku.destroy(app)
      if remotes = git_remotes(Dir.pwd)
        remotes.each do |remote_name, remote_app|
          next if app != remote_app
          git "remote rm #{remote_name}"
        end
      end
      display "done"
    end
  end

end
