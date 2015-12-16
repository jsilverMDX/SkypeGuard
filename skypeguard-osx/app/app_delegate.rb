# It's all lies, you know it.
# Tell me another one.
# Look it up, speak true.
# I suppose you're right all the time, yes you are.
# You're always right all the time, keep it coming
# Why don't you tell me how long, how long now?
# I'm sorry I know, I'm out of touch.
# These won't hold me up no longer
# I've been working on, you know

class AppDelegate < ProMotion::Delegate

  # def quit_app
  #   quit
  # end

  def will_launch(_)
    buildMenu
    @window_screen = MyWindowScreen.new
    open @window_screen
  end

  # def windowShouldClose(sender)
  #   quit
  # end

  def applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
    @window_screen.window.setIsVisible(true)
    return true
  end

end

class MyWindowScreenStylesheet < RubyMotionQuery::Stylesheet
  def label(st)
    st.text = 'SkypeGuard - cam/link blocker'
    st.act_as_label
    st.text_color = color.black
    st.text_alignment = :center
    # st.background_color = color.green
    st.frame = { centered: :horizontal, t: 10, w: 320, h: 30 }
  end

  def button_whitelist(st)
    st.text = 'Whitelist'
    st.frame = { fr: 125, fb: 20, w: 70, h: 50 }
  end

  def button_blacklist(st)
    st.text = 'Remove from Whitelist'
    st.frame = { fr: 200, fb: 20, w: 150, h: 50 }
  end

  def handle(st)
    st.frame = { centered: :horizontal, t: 40, w: 325, h: 30 }
    st.placeholder = 'Skype Handle to whitelist'
  end

  def toggle_linkblocker(st)
    st.text = "Toggle \nLinkblocker"
    st.frame = { fr: 20, fb: 20, w: 100, h: 50 }
  end

end

class MyWindowScreen < ProMotion::WindowScreen
  stylesheet MyWindowScreenStylesheet


  def alert(text, title, &block)
    rmq.app.alert(message: text, title: title, style: :critical, window: self, buttons: ["OK"]) do |result|
      block.call(result) if block_given?
    end
  end


  def update_title(should_link_block)
    # puts "called #{rmq(:label).count}"
    rmq(:label).style {|st| st.text = "SkypeGuard blocking links: #{!!should_link_block} / cam: true"}
  end


  def on_load
    $ad = self
    $window = self.window
    $window.setReleasedWhenClosed(false)
    $window.setStyleMask($window.styleMask & ~NSResizableWindowMask)
    self.window.standardWindowButton(NSWindowMiniaturizeButton).setHidden(true)
    self.window.standardWindowButton(NSWindowZoomButton).setHidden(true)
    # Dispatch::Queue.concurrent.async do
    # alert("SkypeGuard initializing. Currently whitelisted: #{NSUserDefaults.standardUserDefaults[:whitelist].join(', ')}", "Initializing")
    $skype_guard = SkypeGuard.new(self) # will start autoprotecting
    # end
    @label = append(NSTextField, :label)
    update_title($skype_guard.is_link_blocking)
    @handle = append(NSTextField, :handle)
    @toggle_linkblocker = append(NSButton, :toggle_linkblocker).on do
      $skype_guard.should_link_block(!$skype_guard.is_link_blocking)
      alert("Currently link blocking: #{$skype_guard.is_link_blocking}", "Untrusted Links Blocking Status")
      update_title($skype_guard.is_link_blocking)
    end
    @button_whitelist = append(NSButton, :button_whitelist).on do
      handle_text = @handle.get.stringValue
      if handle_text != ""
        Dispatch::Queue.concurrent.async do
          $skype_guard.whitelist(handle_text)
        end
        app.alert(message: "#{handle_text} was whitelisted", title: 'Whitelisted !', style: :critical, window: self, buttons: ['OK']) do |result|
          @handle.get.setStringValue("")
        end
      else
        app.alert(message: "Please enter a handle.", title: 'Error', style: :critical, window: self, buttons: ['OK'])
      end
    end
    @button_blacklist = append(NSButton, :button_blacklist).on do
      handle_text = @handle.get.stringValue
      if handle_text != ""
        Dispatch::Queue.concurrent.async do
          $skype_guard.blacklist(handle_text)
        end
        app.alert(message: "#{handle_text} was removed from whitelist", title: 'Unwhitelisted !', style: :critical, window: self, buttons: ['OK']) do |result|
          @handle.get.setStringValue("")
        end
      else
        app.alert(message: "Please enter a handle.", title: 'Error', style: :critical, window: self, buttons: ['OK'])
      end
    end
  end

  def window_frame
    [[300, 300], [370, 150]]
  end

end