# rbs_inline: enabled
# frozen_string_literal: true

require_relative "diagram/railroad"
require_relative "diagram/states"

module Lrama
  class Diagram
    class << self
      # @rbs (out: IO, grammar: Grammar, template_name: String) -> void
      def render_railroad(out:, grammar:, template_name: 'diagram/diagram.html')
        return unless Railroad.available?
        Railroad.new(grammar).render(out: out, template_name: template_name)
      end

      # @rbs (Lrama::States, format: Symbol, **Hash[Symbol, untyped]) -> String?
      def render_states(states, format: :html, **options)
        return unless States.available?
        States.new(states).render(format: format, **options)
      end

      # @rbs (Lrama::States, String, **Hash[Symbol, untyped]) -> String?
      def render_states_to_file(states, path, **options)
        return unless States.available?
        States.new(states).render_to_file(path, **options)
      end

      # @rbs () -> bool
      def require_railroad_diagrams
        Railroad.available?
      end

      # @rbs () -> bool
      def require_state_diagram
        States.available?
      end
    end
  end
end
