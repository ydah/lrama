# frozen_string_literal: true

require "forwardable"
require_relative "tracer/duration"

module Lrama
  class Output
    extend Forwardable
    include Tracer::Duration

    attr_reader :grammar_file_path, :context, :grammar, :error_recovery, :include_header

    def_delegators "@context", :yyfinal, :yylast, :yyntokens, :yynnts, :yynrules, :yynstates,
                               :yymaxutok, :yypact_ninf, :yytable_ninf

    def_delegators "@grammar", :eof_symbol, :error_symbol, :undef_symbol, :accept_symbol

    def initialize(
      out:, output_file_path:, template_name:, grammar_file_path:,
      context:, grammar:, header_out: nil, header_file_path: nil, error_recovery: false
    )
      @out = out
      @output_file_path = output_file_path
      @template_name = template_name
      @grammar_file_path = grammar_file_path
      @header_out = header_out
      @header_file_path = header_file_path
      @context = context
      @grammar = grammar
      @error_recovery = error_recovery
      @include_header = header_file_path ? header_file_path.sub("./", "") : nil
    end

    if ERB.instance_method(:initialize).parameters.last.first == :key
      def self.erb(input)
        ERB.new(input, trim_mode: '-')
      end
    else
      def self.erb(input)
        ERB.new(input, nil, '-')
      end
    end

    def render_partial(file)
      ERB.render(partial_file(file), context: @context, output: self)
    end

    def render
      report_duration(:render) do
        tmp = eval_template(template_file, @output_file_path)
        @out << tmp

        if @header_file_path
          tmp = eval_template(header_template_file, @header_file_path)

          if @header_out
            @header_out << tmp
          else
            File.write(@header_file_path, tmp)
          end
        end
      end
    end

    # A part of b4_token_enums
    def token_enums
      @context.yytokentype.map do |s_value, token_id, display_name|
        s = sprintf("%s = %d%s", s_value, token_id, token_id == yymaxutok ? "" : ",")

        if display_name
          sprintf("    %-30s /* %s  */\n", s, display_name)
        else
          sprintf("    %s\n", s)
        end
      end.join
    end

    # b4_symbol_enum
    def symbol_enum
      last_sym_number = @context.yysymbol_kind_t.last[1]
      @context.yysymbol_kind_t.map do |s_value, sym_number, display_name|
        s = sprintf("%s = %d%s", s_value, sym_number, (sym_number == last_sym_number) ? "" : ",")

        if display_name
          sprintf("  %-40s /* %s  */\n", s, display_name)
        else
          sprintf("  %s\n", s)
        end
      end.join
    end

    def yytranslate
      int_array_to_string(@context.yytranslate)
    end

    def yytranslate_inverted
      int_array_to_string(@context.yytranslate_inverted)
    end

    def yyrline
      int_array_to_string(@context.yyrline)
    end

    def yytname
      string_array_to_string(@context.yytname) + " YY_NULLPTR"
    end

    # b4_int_type_for
    def int_type_for(ary)
      min = ary.min
      max = ary.max

      case
      when (-127 <= min && min <= 127) && (-127 <= max && max <= 127)
        "yytype_int8"
      when (0 <= min && min <= 255) && (0 <= max && max <= 255)
        "yytype_uint8"
      when (-32767 <= min && min <= 32767) && (-32767 <= max && max <= 32767)
        "yytype_int16"
      when (0 <= min && min <= 65535) && (0 <= max && max <= 65535)
        "yytype_uint16"
      else
        "int"
      end
    end

    def symbol_actions_for_printer
      @grammar.symbols.map do |sym|
        next unless sym.printer

        <<-STR
    case #{sym.enum_name}: /* #{sym.comment}  */
#line #{sym.printer.lineno} "#{@grammar_file_path}"
         {#{sym.printer.translated_code(sym.tag)}}
#line [@oline@] [@ofile@]
        break;

        STR
      end.join
    end

    def symbol_actions_for_destructor
      @grammar.symbols.map do |sym|
        next unless sym.destructor

        <<-STR
    case #{sym.enum_name}: /* #{sym.comment}  */
#line #{sym.destructor.lineno} "#{@grammar_file_path}"
         {#{sym.destructor.translated_code(sym.tag)}}
#line [@oline@] [@ofile@]
        break;

        STR
      end.join
    end

    # b4_user_initial_action
    def user_initial_action(comment = "")
      return "" unless @grammar.initial_action

      <<-STR
        #{comment}
#line #{@grammar.initial_action.line} "#{@grammar_file_path}"
        {#{@grammar.initial_action.translated_code}}
      STR
    end

    def after_shift_function(comment = "")
      return "" unless @grammar.after_shift

      <<-STR
        #{comment}
#line #{@grammar.after_shift.line} "#{@grammar_file_path}"
        {#{@grammar.after_shift.s_value}(#{parse_param_name});}
#line [@oline@] [@ofile@]
      STR
    end

    def before_reduce_function(comment = "")
      return "" unless @grammar.before_reduce

      <<-STR
        #{comment}
#line #{@grammar.before_reduce.line} "#{@grammar_file_path}"
        {#{@grammar.before_reduce.s_value}(yylen#{user_args});}
#line [@oline@] [@ofile@]
      STR
    end

    def after_reduce_function(comment = "")
      return "" unless @grammar.after_reduce

      <<-STR
        #{comment}
#line #{@grammar.after_reduce.line} "#{@grammar_file_path}"
        {#{@grammar.after_reduce.s_value}(yylen#{user_args});}
#line [@oline@] [@ofile@]
      STR
    end

    def after_shift_error_token_function(comment = "")
      return "" unless @grammar.after_shift_error_token

      <<-STR
        #{comment}
#line #{@grammar.after_shift_error_token.line} "#{@grammar_file_path}"
        {#{@grammar.after_shift_error_token.s_value}(#{parse_param_name});}
#line [@oline@] [@ofile@]
      STR
    end

    def after_pop_stack_function(len, comment = "")
      return "" unless @grammar.after_pop_stack

      <<-STR
        #{comment}
#line #{@grammar.after_pop_stack.line} "#{@grammar_file_path}"
        {#{@grammar.after_pop_stack.s_value}(#{len}#{user_args});}
#line [@oline@] [@ofile@]
      STR
    end

    def symbol_actions_for_error_token
      @grammar.symbols.map do |sym|
        next unless sym.error_token

        <<-STR
    case #{sym.enum_name}: /* #{sym.comment}  */
#line #{sym.error_token.lineno} "#{@grammar_file_path}"
         {#{sym.error_token.translated_code(sym.tag)}}
#line [@oline@] [@ofile@]
        break;

        STR
      end.join
    end

    # b4_user_actions
    def user_actions
      action = @context.states.rules.map do |rule|
        next unless rule.token_code

        code = rule.token_code
        spaces = " " * (code.column - 1)

        <<-STR
  case #{rule.id + 1}: /* #{rule.as_comment}  */
#line #{code.line} "#{@grammar_file_path}"
#{spaces}{#{rule.translated_code}}
#line [@oline@] [@ofile@]
    break;

        STR
      end.join

      action + <<-STR

#line [@oline@] [@ofile@]
      STR
    end

    def omit_blanks(param)
      param.strip
    end

    # b4_parse_param
    def parse_param
      if @grammar.parse_param
        omit_blanks(@grammar.parse_param)
      else
        ""
      end
    end

    def lex_param
      if @grammar.lex_param
        omit_blanks(@grammar.lex_param)
      else
        ""
      end
    end

    # b4_user_formals
    def user_formals
      if @grammar.parse_param
        ", #{parse_param}"
      else
        ""
      end
    end

    # b4_user_args
    def user_args
      if @grammar.parse_param
        ", #{parse_param_name}"
      else
        ""
      end
    end

    def extract_param_name(param)
      param[/\b([a-zA-Z0-9_]+)(?=\s*\z)/]
    end

    def parse_param_name
      if @grammar.parse_param
        extract_param_name(parse_param)
      else
        ""
      end
    end

    def lex_param_name
      if @grammar.lex_param
        extract_param_name(lex_param)
      else
        ""
      end
    end

    # b4_parse_param_use
    def parse_param_use(val, loc)
      str = <<-STR.dup
  YY_USE (#{val});
  YY_USE (#{loc});
      STR

      if @grammar.parse_param
        str << "  YY_USE (#{parse_param_name});"
      end

      str
    end

    # b4_yylex_formals
    def yylex_formals
      ary = ["&yylval"]
      ary << "&yylloc" if @grammar.locations

      if @grammar.lex_param
        ary << lex_param_name
      end

      "(#{ary.join(', ')})"
    end

    # b4_table_value_equals
    def table_value_equals(table, value, literal, symbol)
      if literal < table.min || table.max < literal
        "0"
      else
        "((#{value}) == #{symbol})"
      end
    end

    # b4_yyerror_args
    def yyerror_args
      ary = ["&yylloc"]

      if @grammar.parse_param
        ary << parse_param_name
      end

      "#{ary.join(', ')}"
    end

    def template_basename
      File.basename(template_file)
    end

    def aux
      @grammar.aux
    end

    def int_array_to_string(ary)
      last = ary.count - 1

      ary.each_with_index.each_slice(10).map do |slice|
        "  " + slice.map { |e, i| sprintf("%6d%s", e, (i == last) ? "" : ",") }.join
      end.join("\n")
    end

    def spec_mapped_header_file
      @header_file_path
    end

    def b4_cpp_guard__b4_spec_mapped_header_file
      if @header_file_path
        "YY_YY_" + @header_file_path.gsub(/[^a-zA-Z_0-9]+/, "_").upcase + "_INCLUDED"
      else
        ""
      end
    end

    # b4_percent_code_get
    def percent_code(name)
      @grammar.percent_codes.select do |percent_code|
        percent_code.name == name
      end.map do |percent_code|
        percent_code.code
      end.join
    end

    private

    def eval_template(file, path)
      tmp = ERB.render(file, context: @context, output: self)
      replace_special_variables(tmp, path)
    end

    def template_file
      File.join(template_dir, @template_name)
    end

    def header_template_file
      File.join(template_dir, "bison/yacc.h")
    end

    def partial_file(file)
      File.join(template_dir, file)
    end

    def template_dir
      File.expand_path('../../template', __dir__)
    end

    def string_array_to_string(ary)
      result = ""
      tmp = " "

      ary.each do |s|
        replaced = s.gsub('\\', '\\\\\\\\').gsub('"', '\\"')
        if (tmp + replaced + " \"\",").length > 75
          result = "#{result}#{tmp}\n"
          tmp = "  \"#{replaced}\","
        else
          tmp = "#{tmp} \"#{replaced}\","
        end
      end

      result + tmp
    end

    def replace_special_variables(str, ofile)
      str.each_line.with_index(1).map do |line, i|
        line.gsub!("[@oline@]", (i + 1).to_s)
        line.gsub!("[@ofile@]", "\"#{ofile}\"")
        line
      end.join
    end
  end
end
