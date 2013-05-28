require "naught/version"

module Naught
  class NullClassBuilder
    def initialize
      @interface_defined = false
      @operations        = []
      @base_class        = BasicObject
      @inspect_proc      = ->{ "<null>" }
      @stub_strategy     = :stub_method_returning_nil
      define_basic_methods
    end
  
    def interface_defined?
      @interface_defined
    end
  
    def define_explicit_conversions
      defer do |subject|
        subject.module_eval do
          def to_s; ""; end
          def to_i; 0; end
          def to_f; 0.0; end
          def to_c; 0.to_c; end
          def to_r; 0.to_r; end
          def to_a; []; end
          def to_h; {}; end
        end
      end
    end
    def define_implicit_conversions
      defer do |subject|
        subject.module_eval do
          def to_ary; []; end
          def to_str; ''; end
        end
      end
    end
    def root_class_of(klass)
      if klass.ancestors.include?(Object)
        Object
      else
        BasicObject
      end
    end
    def mimic(class_to_mimic, options={})
      include_super = options.fetch(:include_super) { true }
      @base_class   = root_class_of(class_to_mimic)
      @inspect_proc = -> { "<null:#{class_to_mimic}>" }    
      defer do |subject|
        subject.module_eval do
          methods = class_to_mimic.instance_methods(include_super) - 
            Object.instance_methods
          methods.each do |method_name|
            define_method(method_name) {|*| nil}
          end
        end
      end
      @interface_defined = true
    end
    def stub_method_returning_nil(subject, name)
      subject.module_eval do
        define_method(name) {|*| nil }
      end
    end
    
    def stub_method_returning_self(subject, name)
      subject.module_eval do
        define_method(name) {|*| self }
      end
    end
    def stub_method(subject, name)
      send(@stub_strategy, subject, name)
    end
    def black_hole
      @stub_strategy = :stub_method_returning_self
    end
    def respond_to_any_message
      defer do |subject|
        subject.module_eval do
          def respond_to?(*)
            true
          end
        end
        stub_method(subject, :method_missing)
      end
      @interface_defined = true
    end  
    def mimic(class_to_mimic, options={})
      include_super = options.fetch(:include_super) { true }
      @base_class   = root_class_of(class_to_mimic)
      @inspect_proc = -> { "<null:#{class_to_mimic}>" }    
      defer do |subject|
        methods = class_to_mimic.instance_methods(include_super) - 
          Object.instance_methods
        methods.each do |method_name|
          stub_method(subject, method_name)
        end
      end
      @interface_defined = true
    end
    def impersonate(class_to_impersonate, options={})
      mimic(class_to_impersonate, options)
      @base_class = class_to_impersonate
    end
    def traceable
      defer do |subject|
        subject.module_eval do
          attr_reader :__file__, :__line__
    
          def initialize(options={})
            backtrace = options.fetch(:caller) { Kernel.caller(4) }
            @__file__, line, _ = backtrace[0].split(':')
            @__line__ = line.to_i
          end
         end
      end
    end
    def customize(&customization_block)
      return unless customization_block
      customization_module.module_exec(self, &customization_block)
    end
    
    def customization_module
      @customization_module ||= Module.new
    end
    def generate_class
      generation_mod    = Module.new
      customization_mod = customization_module # get a local binding  
      @operations.each do |operation|
        operation.call(generation_mod)
      end
      null_class = Class.new(@base_class) do
        include generation_mod
        include customization_mod
      end
      class_operations.each do |operation|
        operation.call(null_class)
      end
      null_class
    end
    def defer(options={}, &deferred_operation)
      if options[:class]
        class_operations << deferred_operation
      else
        @operations << deferred_operation
      end
    end
    def class_operations
      @class_operations ||= []
    end
    def singleton
      defer(class: true) do |subject|
        require 'singleton'
        subject.module_eval do
          include Singleton
          def self.get(*)
            instance
          end
        end
      end
    end  
    def define_basic_methods
      defer do |subject|
        # make local variable to be accessible to Class.new block
        inspect_proc = @inspect_proc 
        subject.module_eval do
          define_method(:inspect, &inspect_proc)
        end
      end
      defer(class: true) do |subject|
        subject.module_eval do
          class << self
            alias get new
          end
          klass = self
          define_method(:class) { klass }
        end
      end
    end
  end
  def self.build(&customization_block)
    builder = NullClassBuilder.new
    builder.customize(&customization_block)
    unless builder.interface_defined?
      builder.respond_to_any_message
    end
    builder.generate_class
  end
end
