# -*- coding: utf-8 -*-
require 'puppet/interface'
require 'puppet/interface/option'

class Puppet::Interface::Action
  def initialize(face, name, attrs = {})
    raise "#{name.inspect} is an invalid action name" unless name.to_s =~ /^[a-z]\w*$/
    @face    = face
    @name    = name.to_sym
    attrs.each do |k, v| send("#{k}=", v) end

    @options = {}
  end

  # This is not nice, but it is the easiest way to make us behave like the
  # Ruby Method object rather than UnboundMethod.  Duplication is vaguely
  # annoying, but at least we are a shallow clone. --daniel 2011-04-12
  def __dup_and_rebind_to(to)
    bound_version = self.dup
    bound_version.instance_variable_set(:@face, to)
    return bound_version
  end

  attr_reader :name
  def to_s() "#{@face}##{@name}" end

  attr_accessor :default

  ########################################################################
  # Documentation stuff, whee!
  attr_accessor :summary
  def summary=(value)
    value = value.to_s
    value =~ /\n/ and
      raise ArgumentError, "Face summary should be a single line; put the long text in 'description' instead."

    @summary = value
  end


  ########################################################################
  # Initially, this was defined to allow the @action.invoke pattern, which is
  # a very natural way to invoke behaviour given our introspection
  # capabilities.   Heck, our initial plan was to have the faces delegate to
  # the action object for invocation and all.
  #
  # It turns out that we have a binding problem to solve: @face was bound to
  # the parent class, not the subclass instance, and we don't pass the
  # appropriate context or change the binding enough to make this work.
  #
  # We could hack around it, by either mandating that you pass the context in
  # to invoke, or try to get the binding right, but that has probably got
  # subtleties that we don't instantly think of – especially around threads.
  #
  # So, we are pulling this method for now, and will return it to life when we
  # have the time to resolve the problem.  For now, you should replace...
  #
  #     @action = @face.get_action(name)
  #     @action.invoke(arg1, arg2, arg3)
  #
  # ...with...
  #
  #     @action = @face.get_action(name)
  #     @face.send(@action.name, arg1, arg2, arg3)
  #
  # I understand that is somewhat cumbersome, but it functions as desired.
  # --daniel 2011-03-31
  #
  # PS: This code is left present, but commented, to support this chunk of
  # documentation, for the benefit of the reader.
  #
  # def invoke(*args, &block)
  #   @face.send(name, *args, &block)
  # end

  def when_invoked=(block)
    # We need to build an instance method as a wrapper, using normal code, to
    # be able to expose argument defaulting between the caller and definer in
    # the Ruby API.  An extra method is, sadly, required for Ruby 1.8 to work.
    #
    # In future this also gives us a place to hook in additional behaviour
    # such as calling out to the action instance to validate and coerce
    # parameters, which avoids any exciting context switching and all.
    #
    # Hopefully we can improve this when we finally shuffle off the last of
    # Ruby 1.8 support, but that looks to be a few "enterprise" release eras
    # away, so we are pretty stuck with this for now.
    #
    # Patches to make this work more nicely with Ruby 1.9 using runtime
    # version checking and all are welcome, but they can't actually help if
    # the results are not totally hidden away in here.
    #
    # Incidentally, we though about vendoring evil-ruby and actually adjusting
    # the internal C structure implementation details under the hood to make
    # this stuff work, because it would have been cleaner.  Which gives you an
    # idea how motivated we were to make this cleaner.  Sorry. --daniel 2011-03-31

    internal_name = "#{@name} implementation, required on Ruby 1.8".to_sym
    file = __FILE__ + "+eval"
    line = __LINE__ + 1
    wrapper = <<WRAPPER
def #{@name}(*args, &block)
  if args.last.is_a? Hash then
    options = args.last
  else
    args << (options = {})
  end

  action = get_action(#{name.inspect})
  __invoke_decorations(:before, action, args, options)
  rval = self.__send__(#{internal_name.inspect}, *args)
  __invoke_decorations(:after, action, args, options)
  return rval
end
WRAPPER

    if @face.is_a?(Class)
      @face.class_eval do eval wrapper, nil, file, line end
      @face.define_method(internal_name, &block)
    else
      @face.instance_eval do eval wrapper, nil, file, line end
      @face.meta_def(internal_name, &block)
    end
  end

  def add_option(option)
    option.aliases.each do |name|
      if conflict = get_option(name) then
        raise ArgumentError, "Option #{option} conflicts with existing option #{conflict}"
      elsif conflict = @face.get_option(name) then
        raise ArgumentError, "Option #{option} conflicts with existing option #{conflict} on #{@face}"
      end
    end

    option.aliases.each do |name|
      @options[name] = option
    end

    option
  end

  def option?(name)
    @options.include? name.to_sym
  end

  def options
    (@options.keys + @face.options).sort
  end

  def get_option(name, with_inherited_options = true)
    option = @options[name.to_sym]
    if option.nil? and with_inherited_options
      option = @face.get_option(name)
    end
    option
  end

  ########################################################################
  # Support code for action decoration; see puppet/interface.rb for the gory
  # details of why this is hidden away behind private. --daniel 2011-04-15
  private
  def __decorate(type, name, proc)
    @face.__send__ :__decorate, type, name, proc
  end
end
