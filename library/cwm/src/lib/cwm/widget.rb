require "yast"

require "abstract_method"

# Common Widget Manipulation.
# An object-oriented API for the YCP-era {Yast::CWMClass}.
module CWM
  # Represent base for any widget used in CWM. It can be passed as "widget"
  # argument. For more details about usage see {Yast::CWM.show}
  #
  # For using widgets, a design decision is to use *subclasses*. The reason
  # is to have better separeated and easily reusable code. The opposite
  # approach is to use *instances* of existing classes, but especially with
  # storing and initializing widgets it can be quite complex.
  #
  # @example InputField with instances
  #   widget = InputField.new(
  #     label: _("My label"),
  #     help: _("blablabla" \
  #       "blablabla" \
  #       "blablabla"
  #     ),
  #     init: Proc.new do
  #       ...
  #     end,
  #     store: Proc.new do
  #       ...
  #     end,
  #     validate: Proc.new do
  #       ....
  #     end
  #   )
  #
  # @example InputFieldwith subclasses
  #   class MyWidget < CWM::InputField
  #     def label
  #       _("My label")
  #     end
  #
  #     def help
  #       _("blablabla" \
  #         "blablabla" \
  #         "blablabla"
  #     end
  #
  #     def init
  #       ...
  #     end
  #
  #     def store
  #       ...
  #     end
  #
  #     def validate
  #       ....
  #     end
  #   end
  #
  #   widget = MyWidget.new
  class AbstractWidget
    include Yast::UIShortcuts
    include Yast::I18n

    # By default, {#handle} has no argument and it is called
    # only for events of its own widget.
    # If true, {#handle}(event) is called for events of any widget.
    # @return [Boolean]
    def handle_all_events
      @handle_all_events.nil? ? false : @handle_all_events
    end
    attr_writer :handle_all_events

    # @return [String] An ID, unique within a dialog, used for the widget.
    #   By default, the class name is used.
    def widget_id
      @widget_id || self.class.to_s
    end
    attr_writer :widget_id

    # Declare widget type for {Yast::CWMClass}.
    # Your derived widgets will not need to do this.
    # @param type [Symbol]
    # @return [void]
    def self.widget_type=(type)
      define_method(:widget_type) { type }
    end

    # The following methods are only documented but not defined
    # because we do not want to accidentally override the subtle defaults
    # used by Yast::CWMClass.

    # @!method help
    #   @return [String] translated help text for the widget

    # @!method label
    #   Derived classes must override this method to specify a label.
    #   @return [String] translated label text for the widget

    # @!method opt
    #   @return [Array<Symbol>] options passed to widget
    #     like `[:hstretch, :vstretch]`

    # @!method init
    #   Initialize the widget: set initial value
    #   @return [void]

    # @!method handle(*args)
    # @overload handle
    #   Process an event generated by this widget. This method is invoked
    #   if {#handle_all_events} is `false`.
    #   @return [nil,Symbol] what to return from the dialog,
    #     or `nil` to continue processing
    # @overload handle(event)
    #   Process an event generated a widget. This method is invoked
    #   if {#handle_all_events} is `true`.
    #   @param event [Hash] see CWMClass
    #   @return [nil,Symbol] what to return from the dialog,
    #     or `nil` to continue processing

    # @!method validate
    #   Validate widgets before ending the loop and storing.
    #   @return [Boolean] validate widget value.
    #     If it fails (`false`) the dialog will not return yet.

    # @!method store
    #   Store the widget value for further processing
    #   @return [void]

    # @!method cleanup
    #   Clean up after the widget is destroyed
    #   @return [void]

    # Generate widget definition for {Yast::CWMClass}.
    # It refers to
    # {#help}, {#label}, {#opt}
    # {#validate}, {#init}, {#handle}, {#store}, {#cleanup}.
    # @return [Hash{String => Object}]
    # @raise [RuntimeError] if a required method is not implemented
    #   or widget_type is not set.
    def cwm_definition
      if !respond_to?(:widget_type)
        raise "Widget '#{self.class}' does set its widget type"
      end

      res = {}

      if respond_to?(:help)
        res["help"] = help
      else
        res["no_help"] = ""
      end
      res["label"] = label if respond_to?(:label)
      res["opt"] = opt if respond_to?(:opt)
      if respond_to?(:validate)
        res["validate_function"] = validate_method
        res["validate_type"] = :function
      end
      res["handle_events"] = [widget_id] unless handle_all_events
      res["init"] = init_method if respond_to?(:init)
      res["handle"] = handle_method if respond_to?(:handle)
      res["store"] = store_method if respond_to?(:store)
      res["cleanup"] = cleanup_method if respond_to?(:cleanup)
      res["widget"] = widget_type

      res
    end

    # @return [Boolean] Is widget open for interaction?
    def enabled?
      Yast::UI.QueryWidget(Id(widget_id), :Enabled)
    end

    # Opens widget for interaction
    # @return [void]
    def enable
      Yast::UI.ChangeWidget(Id(widget_id), :Enabled, true)
    end

    # Closes widget for interaction
    # @return [void]
    def disable
      Yast::UI.ChangeWidget(Id(widget_id), :Enabled, false)
    end

  protected

    # A helper to check if an event is invoked by this widget
    # @param event [Hash] a UI event
    def my_event?(event)
      widget_id == event["ID"]
    end

    # shortcut from Yast namespace to avoid including whole namespace
    # @todo kill converts in CWM module, to avoid this workaround for funrefs
    # @return [Yast::FunRef]
    def fun_ref(*args)
      Yast::FunRef.new(*args)
    end

  private

    # @note all methods here use wrappers to modify required parameters as CWM
    # have not so nice callbacks API
    def init_method
      fun_ref(method(:init_wrapper), "void (string)")
    end

    def init_wrapper(_widget_id)
      init
    end

    def handle_method
      fun_ref(method(:handle_wrapper), "symbol (string, map)")
    end

    # allows both variant of handle. with event map and without.
    # with map it make sense when handle_all_events is true or in custom widgets
    # with multiple elements, that generate events, otherwise map is not needed
    def handle_wrapper(_widget_id, event)
      m = method(:handle)
      if m.arity == 0
        m.call
      else
        m.call(event)
      end
    end

    def store_method
      fun_ref(method(:store_wrapper), "void (string, map)")
    end

    def store_wrapper(_widget_id, _event)
      store
    end

    def cleanup_method
      fun_ref(method(:cleanup_wrapper), "void (string)")
    end

    def cleanup_wrapper(_widget_id)
      cleanup
    end

    def validate_method
      fun_ref(method(:validate_wrapper), "boolean (string, map)")
    end

    def validate_wrapper(_widget_id, _event)
      validate
    end
  end

  # A custom widget that has its UI content defined in the method {#contents}.
  # Useful mainly when a specialized widget including more subwidgets should be
  # reusable at more places.
  #
  # @example custom widget child
  #   class MyWidget < CWM::CustomWidget
  #     def initialize
  #       self.handle_all_events = true
  #     end
  #
  #     def contents
  #       HBox(
  #         PushButton(Id(:reset), _("Reset")),
  #         PushButton(Id(:undo), _("Undo"))
  #       )
  #     end
  #
  #     def handle(event)
  #       case event["ID"]
  #       when :reset then ...
  #       when :undo then ...
  #       else ...
  #       end
  #       nil
  #     end
  #   end
  class CustomWidget < AbstractWidget
    self.widget_type = :custom

    # @!method contents
    #   Must be defined by subclasses
    #   @return [Yast::Term] a UI term; {AbstractWidget} are not allowed inside
    abstract_method :contents

    def cwm_definition
      res = { "custom_widget" => cwm_contents }

      res["handle_events"] = ids_in_contents unless handle_all_events

      super.merge(res)
    end

    # Returns all nested widgets used in contents
    def nested_widgets
      Yast.import "CWM"

      Yast::CWM.widgets_in_contents(contents)
    end

  protected

    # return contents converted to format understandable by CWM module
    # Basically it replace instance of AbstractWidget by its widget_id
    def cwm_contents
      Yast.import "CWM"

      Yast::CWM.widgets_contents(contents)
    end

    def ids_in_contents
      find_ids(contents) << widget_id
    end

    def find_ids(term)
      term.each_with_object([]) do |arg, res|
        next unless arg.is_a? Yast::Term

        if arg.value == :id
          res << arg.params[0]
        else
          res.concat(find_ids(arg))
        end
      end
    end
  end

  # An empty widget useful mainly as placeholder for replacement
  # or for catching global events
  #
  # @example empty widget usage
  #   CWM.show(VBox(CWM::Empty.new("replace_point")))
  class Empty < AbstractWidget
    self.widget_type = :empty

    # @param id [String] widget ID
    def initialize(id)
      self.widget_id = id
    end
  end

  # A mix-in for widgets using the :Value property
  module ValueBasedWidget
    # Get widget value
    # @return [Object] a value according to specific widget type
    def value
      Yast::UI.QueryWidget(Id(widget_id), :Value)
    end

    # Set widget value
    # @param val [Object] a value according to specific widget type
    # @return [void]
    def value=(val)
      Yast::UI.ChangeWidget(Id(widget_id), :Value, val)
    end
  end

  # A mix-in to define items used by widgets
  # that offer a selection from a list of values.
  module ItemsSelection
    # Items are defined as a list of pairs, where
    # the first one is the ID and
    # the second one is the user visible value
    # @return [Array<Array(String,String)>]
    # @example items method in widget
    #   def items
    #     [
    #       [ "Canada", _("Canada")],
    #       [ "USA", _("United States of America")],
    #       [ "North Pole", _("Really cold place")],
    #     ]
    #   end
    def items
      []
    end

    def cwm_definition
      super.merge(
        "items" => items
      )
    end

    # Change the list of items offered in widget.
    # The format is the same as in {#items}
    # @param items_list [Array<Array(String,String)>] new items
    # @return [void]
    def change_items(items_list)
      val = items_list.map { |i| Item(Id(i[0]), i[1]) }

      Yast::UI.ChangeWidget(Id(widget_id), :Items, val)
    end
  end

  # An input field widget.
  # The {#label} method is mandatory.
  #
  # @example input field widget child
  #   class MyWidget < CWM::InputField
  #     def initialize(myconfig)
  #       @config = myconfig
  #     end
  #
  #     def label
  #       _("The best widget ever is:")
  #     end
  #
  #     def init
  #       self.value = @config.value
  #     end
  #
  #     def store
  #       @config.value = value
  #     end
  #   end
  class InputField < AbstractWidget
    self.widget_type = :inputfield

    include ValueBasedWidget
    abstract_method :label
  end

  # A Password widget.
  # The {#label} method is mandatory.
  #
  # @see InputField for example of child
  class Password < AbstractWidget
    self.widget_type = :password

    include ValueBasedWidget
    abstract_method :label
  end

  # A CheckBox widget.
  # The {#label} method is mandatory.
  #
  # @see InputField for example of child
  class CheckBox < AbstractWidget
    self.widget_type = :checkbox

    include ValueBasedWidget
    abstract_method :label

    # @return [Boolean] true if the box is checked
    def checked?
      value == true
    end

    # @return [Boolean] true if the box is unchecked
    def unchecked?
      # explicit check as the value can be also nil,
      # which is shown as a grayed-out box, with "indeterminate" meaning
      value == false
    end

    # Checks the box
    # @return [void]
    def check
      self.value = true
    end

    # Unchecks the box
    # @return [void]
    def uncheck
      self.value = false
    end
  end

  # A Combo box to select a value.
  # The {#label} method is mandatory.
  #
  # @example combobox widget child
  #   class MyWidget < CWM::ComboBox
  #     def initialize(myconfig)
  #       @config = myconfig
  #     end
  #
  #     def label
  #       _("Choose carefully:")
  #     end
  #
  #     def init
  #       self.value = @config.value
  #     end
  #
  #     def store
  #       @config.value = value
  #     end
  #
  #     def items
  #       [
  #         [ "Canada", _("Canada")],
  #         [ "USA", _("United States of America")],
  #         [ "North Pole", _("Really cold place")],
  #       ]
  #     end
  #   end
  class ComboBox < AbstractWidget
    self.widget_type = :combobox

    include ValueBasedWidget
    include ItemsSelection
    abstract_method :label
  end

  # Widget representing selection box to select value.
  # The {#label} method is mandatory.
  #
  # @see ComboBox for child example
  class SelectionBox < AbstractWidget
    self.widget_type = :selection_box

    include ItemsSelection
    abstract_method :label

    # @return [String] ID of the selected item
    def value
      Yast::UI.QueryWidget(Id(widget_id), :CurrentItem)
    end

    # @param val [String] ID of the selected item
    def value=(val)
      Yast::UI.ChangeWidget(Id(widget_id), :CurrentItem, val)
    end
  end

  # A multi-selection box to select more values.
  # The {#label} method is mandatory.
  #
  # @see {ComboBox} for child example
  class MultiSelectionBox < AbstractWidget
    self.widget_type = :multi_selection_box

    include ItemsSelection
    abstract_method :label

    # @return [Array<String>] return IDs of selected items
    def value
      Yast::UI.QueryWidget(Id(widget_id), :SelectedItems)
    end

    # @param val [Array<String>] IDs of newly selected items
    def value=(val)
      Yast::UI.ChangeWidget(Id(widget_id), :SelectedItems, val)
    end
  end

  # An integer field widget.
  # The {#label} method is mandatory.
  # It supports optional {#minimum} and {#maximum} methods
  # for limiting the range.
  # See {#cwm_definition} method for minimum and maximum example
  #
  # @see InputField for example of child
  class IntField < AbstractWidget
    self.widget_type = :intfield

    include ValueBasedWidget
    abstract_method :label

    # @!method minimum
    #   @return [Fixnum] limited by C signed int range (-2**30 to 2**31-1).

    # @!method maximum
    #   @return [Fixnum] limited by C signed int range (-2**30 to 2**31-1).

    # The definition for IntField additionally supports
    # `minimum` and `maximum` methods.
    # @example minimum and maximum methods
    #   def minimum
    #     50
    #   end
    #
    #   def maximum
    #     200
    #   end
    def cwm_definition
      res = {}

      res["minimum"] = minimum if respond_to?(:minimum)
      res["maximum"] = maximum if respond_to?(:maximum)

      super.merge(res)
    end
  end

  # A selection of a value via radio buttons.
  # The {#label} method is mandatory.
  #
  # @see {ComboBox} for child example
  class RadioButtons < AbstractWidget
    self.widget_type = :radio_buttons

    include ItemsSelection
    abstract_method :label

    def value
      Yast::UI.QueryWidget(Id(widget_id), :CurrentButton)
    end

    def value=(val)
      Yast::UI.ChangeWidget(Id(widget_id), :CurrentButton, val)
    end
  end

  # Widget representing button.
  #
  # @example push button widget child
  #   class MyEvilWidget < CWM::PushButton
  #     def label
  #       _("Win the lottery by clicking this.")
  #     end
  #
  #     def handle
  #       Virus.install
  #       nil
  #     end
  #   end
  class PushButton < AbstractWidget
    self.widget_type = :push_button

    abstract_method :label
  end

  # Widget representing menu button with its submenu
  class MenuButton < AbstractWidget
    self.widget_type = :menu_button

    include ItemsSelection
    abstract_method :label
  end

  # Multiline text widget
  # @note label method is required and used as default value (TODO: incosistent with similar richtext in CWM itself)
  class MultiLineEdit < AbstractWidget
    self.widget_type = :multi_line_edit

    include ValueBasedWidget
    abstract_method :label
  end

  # Rich text widget supporting some highlighting
  class RichText < AbstractWidget
    self.widget_type = :richtext

    include ValueBasedWidget
  end

  # Tab widget, usefull only with {CWM::Tabs}
  # @see tabs example for usage
  class Tab < CustomWidget
    # @return [Boolean] is this the initially selected tab
    attr_accessor :initial

    # @return [Yast::Term] contents of the tab, can contain {AbstractWidget}s
    abstract_method :contents
    # @return [String] label defines name of tab header
    abstract_method :label

    def cwm_definition
      super.merge(
        "widgets"       => cwm_widgets,
        "custom_widget" => Yast::CWM.PrepareDialog(cwm_contents, cwm_widgets)
      )
    end

    # get cwm style of widget definitions
    # @note internal api only used as gate to communicate with CWM
    def cwm_widgets
      return @cwm_widgets if @cwm_widgets

      widgets = nested_widgets
      names = widgets.map(&:widget_id)
      definition = Hash[widgets.map { |w| [w.widget_id, w.cwm_definition] }]
      @cwm_widgets = Yast::CWM.CreateWidgets(names, definition)
    end

  protected

    # help that is result of used widget helps.
    # If overwritting, do not forget to use `super`, otherwise widget helps will
    # be missing
    def help
      Yast::CWM.MergeHelps(nested_widgets.map(&:cwm_definition))
    end
  end

  # useful to have tabs as widget. It contained {CWM::Tab} with its content
  # @see examples/object_api_tabs.rb
  class Tabs < CustomWidget
    # param [Array<CWM::Tab>] tabs to be shown
    def initialize(*tabs)
      @tabs = tabs
      @current_tab = nil
      self.handle_all_events = true
    end

    # initializes tabs, show tab which is initial
    def init
      switch_tab(initial_tab_id)
    end

    def handle(event)
      # pass it to content of tab at first, maybe something stop passing
      res = Yast::CWM.handleWidgets(@current_tab.cwm_widgets, event)
      return res if res

      new_id = event["ID"]
      tab = tab_for_id(new_id)

      return nil unless tab

      return nil if @current_tab.widget_id == new_id

      unless validate
        mark_tab(@current_tab)
        return nil
      end

      store_tab(@current_tab.widget_id)

      switch_tab(new_id)

      nil
    end

    # store content of current tab
    def store
      store_tab(@current_tab.widget_id)
    end

    # validates current tab
    def validate
      Yast::CWM.validateWidgets(@current_tab.cwm_definition["widgets"], "ID" => @current_tab.widget_id)
    end

  protected

    # gets visual order of tabs
    # This default implementation returns same order as passed to constructor
    def tab_order
      @tabs.map(&:widget_id)
    end

    # stores tab with given id
    def store_tab(tab_id)
      Yast::CWM.saveWidgets(tab_for_id(tab_id).cwm_definition["widgets"], "ID" => tab_id)
    end

    # switch to target tab
    def switch_tab(tab_id)
      tab = tab_for_id(tab_id)
      return unless tab

      mark_tab(tab)
      Yast::UI.ReplaceWidget(Id(replace_point_id), tab.cwm_definition["custom_widget"])
      Yast::CWM.initWidgets(tab.cwm_definition["widgets"])
      @current_tab = tab
    end

    # visually mark currently active tab
    def mark_tab(tab)
      if Yast::UI.HasSpecialWidget(:DumbTab)
        Yast::UI.ChangeWidget(Id(widget_id), :CurrentItem, tab.widget_id)
      else
        if @current_tab
          Yast::UI.ChangeWidget(
            Id(@current_tab.widget_id),
            :Label,
            @current_tab.label
          )
        end
        Yast::UI.ChangeWidget(
          Id(tab.widget_id),
          :Label,
          "#{Yast::UI.Glyph(:BulletArrowRight)}  #{tab.label}"
        )
      end
    end

    # gets id of initial tab
    # This default implementation returns first tab from {#tabs} method
    def initial_tab_id
      initial = @tabs.find(&:initial)

      (initial || @tabs.first).widget_id
    end

    def contents
      if Yast::UI.HasSpecialWidget(:DumbTab)
        panes = tab_order.map do |tab_id|
          tab = tab_for_id(tab_id)
          Item(Id(tab.widget_id), tab.label, tab.widget_id == initial_tab_id)
        end
        DumbTab(Id(widget_id), panes, replace_point)
      else
        tabbar = tab_order.each_with_object(HBox()) do |tab, res|
          tab = tab_for_id(tab)
          res << PushButton(Id(tab.widget_id), tab.label)
        end
        VBox(Left(tabbar), Frame("", replace_point))
      end
    end

    def tab_for_id(id)
      @tabs.find { |t| t.widget_id == id }
    end

  private

    def replace_point_id
      :_cwm_tab_contents_rp
    end

    def replace_point
      ReplacePoint(Id(replace_point_id), VBox(VStretch(), HStretch()))
    end
  end
end
