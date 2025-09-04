# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Reporter
    class Rules
      # @rbs (?rules: bool, ?mode: Symbol, **untyped _) -> void
      def initialize(rules: false, mode: :text, **_)
        @rules = rules
        @mode = mode
      end

      # @rbs (IO io, Lrama::States states) -> void
      def report(io, states)
        return unless @rules

        used_rules = states.rules.flat_map(&:rhs)
        frequency_counts = used_rules.each_with_object(Hash.new(0)) { |rule, counts| counts[rule] += 1 }
        sorted_frequency = frequency_counts
                           .select { |rule,| !rule.midrule? }
                           .sort_by { |rule, count| [-count, rule.name] }

        unused_rules = states.rules.map(&:lhs).select do |rule|
          !used_rules.include?(rule) && rule.token_id != 0
        end

        case @mode
        when :text
          report_text(io, sorted_frequency, unused_rules)
        when :html
          report_html(io, sorted_frequency, unused_rules)
        else
          raise "Unknown mode: #{@mode.inspect}"
        end
      end

      private

      # @rbs (IO io, Array[untyped] sorted_frequency, Array[Lrama::Grammar::Symbol] unused_rules) -> void
      def report_html(io, sorted_frequency, unused_rules)
        io << %Q(<div id="rule-usage">\n)

        unless sorted_frequency.empty?
          io << %Q(  <h2>Rule Usage Frequency</h2>\n)
          io << %Q(  <pre>\n)
          sorted_frequency.each_with_index do |(rule, count), i|
            io << sprintf("   %d %s (%d times)", i, rule.name, count) << "\n"
          end
          io << %Q(  </pre>\n)
        end

        unless unused_rules.empty?
          io << %Q(  <h3>Unused Rules</h3>\n)
          io << %Q(  <pre>\n)
          unused_rules.each_with_index do |rule, index|
            io << sprintf("   %d %s", index, rule.display_name) << "\n"
          end
          io << %Q(  </pre>\n)
        end

        io << %Q(</div>\n)
      end

      # @rbs (IO io, Array[untyped] sorted_frequency, Array[Lrama::Grammar::Symbol] unused_rules) -> void
      def report_text(io, sorted_frequency, unused_rules)
        unless sorted_frequency.empty?
          io << "Rule Usage Frequency\n\n"
          sorted_frequency.each_with_index do |(rule, count), i|
            io << sprintf("%5d %s (%d times)", i, rule.name, count) << "\n"
          end
          io << "\n\n"
        end

        unless unused_rules.empty?
          io << "#{unused_rules.count} Unused Rules\n\n"
          unused_rules.each_with_index do |rule, index|
            io << sprintf("%5d %s", index, rule.display_name) << "\n"
          end
          io << "\n\n"
        end
      end
    end
  end
end
