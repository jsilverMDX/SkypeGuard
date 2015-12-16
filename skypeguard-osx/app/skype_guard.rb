# require 'skype'
# require 'pstore'
# require "active_support/all"

# SkypeGuard
# op2600

class SkypeGuard

  attr_accessor :whitelisted_handles, :duration

  def is_link_blocking
    @should_link_block
  end

  def should_link_block(s)
    @should_link_block = s
    @store[:should_link_block] = s
  end

  def quiet?
    true
  end

  def whitelist(handle)
    @whitelisted_handles << handle unless @whitelisted_handles.include?(handle)
    @store[:whitelist] = @whitelisted_handles
  end

  def blacklist(handle)
    @whitelisted_handles.delete(handle)
    @store[:whitelist] = @whitelisted_handles
    @store[handle] = Time.new # we just met them
  end

  def block_unauthorized_video

    active_call = Skype.exec("SEARCH ACTIVECALLS").split(" ")

    return if active_call.include?("missing value")

    active_call = active_call.last

    puts active_call unless quiet?

    return if active_call == "CALLS" || active_call == "COMMAND_PENDING"

    partner_handle = Skype.exec("GET CALL #{active_call} PARTNER_HANDLE").split(" ").last

    puts partner_handle unless quiet?

    if !partner_handle.nil?
      @seen_before = @store[partner_handle]
    else
      return
    end

    unless @whitelisted_handles.include?(partner_handle)
      unless @seen_before
        puts "we havent seen #{partner_handle} before. adding to database. video will be denied." unless quiet?
        # @delegate.alert("we havent seen #{partner_handle} before. adding to database. video will be denied.", "denying video")
        if !partner_handle.nil?
          @store[partner_handle] = Time.new
        else
          return
        end
        deny_remote_video(active_call)
        deny_local_video(active_call)
      else
        puts "we saw #{partner_handle} first at #{@seen_before}" unless quiet?
        if(@seen_before > 3.days.ago)
          puts "#{partner_handle} was not seen more than 3 days ago, blocking video" unless quiet?
          deny_remote_video(active_call)
          deny_local_video(active_call)
        end
      end
    else
      puts "#{partner_handle} is whitelisted. not blocking video." unless quiet?
    end

  end

  def deny_remote_video(call_id)
    Skype.exec("ALTER CALL #{call_id} STOP_VIDEO_RECEIVE") if receiving_video?(call_id)
  end

  def deny_local_video(call_id)
    Skype.exec("ALTER CALL #{call_id} STOP_VIDEO_SEND") if sending_video?(call_id)
  end

  def receiving_video?(call_id)
    Skype.exec("GET CALL #{call_id} VIDEO_RECEIVE_STATUS").split(" ").last == "RUNNING"
  end

  def sending_video?(call_id)
    Skype.exec("GET CALL #{call_id} VIDEO_SEND_STATUS").split(" ").last == "RUNNING"
  end


  def block_unauthorized_links # whitelist is mandatory
    return if !is_link_blocking
    recent_chats = Skype.exec "SEARCH RECENTCHATS"
    return if recent_chats == "CHATS" || recent_chats == "COMMAND_PENDING" || recent_chats.include?("missing value") # nothing to be done ...
    chat_ids = recent_chats.split("CHATS ").last.split(", ")
    chat_ids.each do |current_chat_id|
      handle = current_chat_id.split("#").last.split('/$').first
      puts "handle: #{handle} whitelisted: #{@whitelisted_handles.include?(handle)}" unless quiet?
      recent_messages = Skype.exec "GET CHAT #{current_chat_id} RECENTCHATMESSAGES"
      puts "recent_messages #{recent_messages}" unless quiet?
      last_message_id = recent_messages.split(" RECENTCHATMESSAGES ").last.split(", ").last
      puts "last_message_id #{last_message_id}" unless quiet?
      message_body = Skype.exec("GET CHATMESSAGE #{last_message_id} BODY").split(" BODY ").last
      puts "message_body: #{message_body}" unless quiet?
      from_handle = Skype.exec("GET CHATMESSAGE #{last_message_id} FROM_HANDLE").split(" FROM_HANDLE ").last
      puts "from_handle: #{from_handle}" unless quiet?
      my_handle = Skype.exec("GET CURRENTUSERHANDLE").split(" ").last
      puts "my_handle: #{my_handle}" unless quiet?
      return if from_handle == my_handle
      if from_handle != nil # if the chat or handle is over 10 days old, it's probably not malicious
        if @store[from_handle] > 10.days.ago
          return
        end
      end
      if(!@whitelisted_handles.include?(handle))&&(message_body.include?("http://") || message_body.include?("https://") || message_body.include?("www."))
        active_call = Skype.exec("SEARCH ACTIVECALLS").split(" ").last
        if active_call != "CALLS"
          Skype.exec "ALTER CALL #{active_call} HANGUP"
        end
        Skype.exec "CLEAR CHATHISTORY" # probably needed to sanitize/close chat
        # Skype.exec "ALTER CHAT #{current_chat_id} CLEARRECENTMESSAGES" # wont work...
        Skype.exec "ALTER CHAT #{current_chat_id} LEAVE"
        # @delegate.alert("Unauthorized link detected. Cleared chat history and left chat.", "Unauthorized link blocked")
      end
    end
  end

  def online?
    conn_status = Skype.exec("GET CONNSTATUS")
    return false if conn_status.include?("missing value")
    conn_status = conn_status.split(" ").last
    if conn_status == "ONLINE"
      @duration = 0.1
    else
      @duration = 7
    end
    (conn_status != "OFFLINE") && (conn_status != "COMMAND_PENDING")
  end

  def look_out_for_unauthorized_video_and_links

    loop do

      begin
        if online?
          block_unauthorized_video
          block_unauthorized_links
        else
          puts "offline.. doing nothing" unless quiet?
        end
      rescue
        puts "no call to monitor" unless quiet?
      end

      sleep @duration || 7

    end

  end

  def initialize(delegate)

      $queue = Dispatch::Queue.concurrent.async do

        @delegate = delegate

        Skype.config :app_name => "SkypeGuard"

        @store = NSUserDefaults.standardUserDefaults

        @store[:whitelist] = @store[:whitelist].nil? ? [] : @store[:whitelist]

        @store[:should_link_block] = @store[:should_link_block].nil? ? false : @store[:should_link_block]

        should_link_block(@store[:should_link_block])

        @whitelisted_handles = @store[:whitelist].clone # names of people you trust

        look_out_for_unauthorized_video_and_links

      end

  end


end




class Skype

  def self.config(options)
    @app_name = options[:app_name]
  end


  def self.exec(command)
    script = %Q{tell application "System Events"
                  set skypeIsNotRunning to not (exists process "Skype")
                end tell
                if skypeIsNotRunning then
                  activate "Skype"
                end if
                tell application "Skype"
                  send command "#{command}" script name "#{@app_name}"
                end tell
                }
    res = `unset LD_LIBRARY_PATH; unset DYLD_LIBRARY_PATH; /usr/bin/osascript -e '#{script}'`.strip
    res
  end

end
