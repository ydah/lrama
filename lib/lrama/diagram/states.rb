# rbs_inline: enabled
# frozen_string_literal: true

require_relative "states_adapter"

module Lrama
  class Diagram
    class States
      attr_reader :states

      # @rbs (Lrama::States states) -> void
      def initialize(states)
        @states = states
      end

      # @rbs () -> bool
      def self.available?
        require "automograph"
        true
      rescue LoadError
        false
      end

      # @rbs () -> void
      def self.require!
        require "automograph"
      rescue LoadError
        warn "automograph is not installed. Please run `bundle install`."
        raise
      end

      # @rbs (format: Symbol, **Hash[Symbol, untyped]) -> String
      def render(format: :html, **options)
        self.class.require!
        model = build_model(name: options.delete(:name))
        Automograph.render(model, format: format, **options)
      end

      # @rbs (String, **Hash[Symbol, untyped]) -> String
      def render_to_file(path, **options)
        self.class.require!
        model = build_model(name: options.delete(:name))
        Automograph.render_to_file(model, path, **options)
      end

      private

      # @rbs (name: String?) -> Automograph::Model
      def build_model(name: nil)
        StatesAdapter.new(@states).build(name: name)
      end
    end
  end
end
