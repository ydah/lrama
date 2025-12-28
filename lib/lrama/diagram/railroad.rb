# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Diagram
    class Railroad
      attr_reader :grammar

      # @rbs (Grammar grammar) -> void
      def initialize(grammar)
        @grammar = grammar
      end

      # @rbs () -> bool
      def self.available?
        require "railroad_diagrams"
        true
      rescue LoadError
        false
      end

      # @rbs () -> void
      def self.require!
        require "railroad_diagrams"
      rescue LoadError
        warn "railroad_diagrams is not installed. Please run `bundle install`."
        raise
      end

      # @rbs (out: IO, template_name: String) -> void
      def render(out:, template_name: 'diagram/diagram.html')
        self.class.require!
        RailroadDiagrams::TextDiagram.set_formatting(RailroadDiagrams::TextDiagram::PARTS_UNICODE)
        out << ERB.render(template_file(template_name), output: self)
      end

      # @rbs () -> string
      def default_style
        RailroadDiagrams::Style::default_style
      end

      # @rbs () -> string
      def diagrams
        result = +''
        @grammar.unique_rule_s_values.each do |s_value|
          diagrams = @grammar.select_rules_by_s_value(s_value).map { |r| r.to_diagrams }
          add_diagram(
            s_value,
            RailroadDiagrams::Diagram.new(
              RailroadDiagrams::Choice.new(0, *diagrams),
            ),
            result
          )
        end
        result
      end

      private

      # @rbs () -> string
      def template_dir
        File.expand_path('../../../template', __dir__)
      end

      # @rbs (String name) -> string
      def template_file(name)
        File.join(template_dir, name)
      end

      # @rbs (String name, RailroadDiagrams::Diagram diagram, String result) -> void
      def add_diagram(name, diagram, result)
        result << "\n<h2 class=\"diagram-header\">#{RailroadDiagrams.escape_html(name)}</h2>"
        diagram.write_svg(result.method(:<<))
        result << "\n"
      end
    end
  end
end
