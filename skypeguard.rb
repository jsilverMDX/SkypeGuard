require 'skype'
require 'pstore'
require "active_support/all"

Skype.config :app_name => "SkypeGuard"

@store = PStore.new("data.pstore")

@whitelist = [] # names of people you trust

def block_unauthorized_video

  active_call = Skype.exec("SEARCH ACTIVECALLS").split(" ").last

  puts active_call

  partner_handle = Skype.exec("GET CALL #{active_call} PARTNER_HANDLE").split(" ").last

  puts partner_handle

  @store.transaction do
    @seen_before = @store[partner_handle]
  end

  unless @whitelist.include?(partner_handle)
    unless @seen_before
      puts "we havent seen #{partner_handle} before. adding to database. video will be denied."
      Thread.new do
        alert("we havent seen #{partner_handle} before. adding to database. video will be denied.")
      end
      @store.transaction do
        @store[partner_handle] = Time.new
      end
      deny_remote_video
      deny_local_video
    else
      puts "we saw #{partner_handle} first at #{@seen_before}"
      if(@seen_before > 3.days.ago)
        puts "#{partner_handle} was not seen more than 3 days ago, blocking video"
        deny_remote_video(active_call)
        deny_local_video(active_call)
      end
    end
  else
    puts "#{partner_handle} is whitelisted. not blocking video."
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


def look_out_for_unauthorized_video

    loop do

      begin
        block_unauthorized_video
      rescue
        puts "no call to monitor"
      end

      sleep 0.1

    end

end

def alert(text)
  script = <<-END
   tell application "System Events"
     display dialog "#{text}"
   end tell
  END
  system 'osascript', *script.split(/\n/).map { |line| ['-e', line] }.flatten
end

look_out_for_unauthorized_video




