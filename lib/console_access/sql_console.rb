# frozen_string_literal: true

module ConsoleAccess
  # The SQL console that `bin/rails dbconsole` opens in a protected
  # environment, in place of psql. A superadmin approves it like the Rails
  # console, and Console1984 records the reason and every statement, so the
  # session shows in /admin/console next to the Rails console sessions.
  #
  # End a statement with a semicolon. \dt lists the tables, \d TABLE lists the
  # columns of a table, and \q (or Ctrl-D) quits.
  class SqlConsole
    PROMPT = "sql> "
    CONTINUATION_PROMPT = "...> "
    MAX_CELL_WIDTH = 60
    QUIT_COMMANDS = %w[\q exit quit].freeze

    LIST_TABLES_SQL = <<~SQL.squish
      SELECT table_name FROM information_schema.tables
      WHERE table_schema = current_schema() ORDER BY table_name
    SQL

    def initialize(db_config:, input: nil, output: $stdout, approval: Approval.new(kind: "sql"))
      @db_config = db_config
      @input = input || method(:read_with_reline)
      @output = output
      @approval = approval
    end

    def start
      user = @approval.await!
      reason = read_reason
      Console1984.session_logger.start_session(ConsoleAccess.username_for(user), "SQL (#{@db_config.name}): #{reason}")
      @output.puts "Connected to #{@db_config.name} as #{ConsoleAccess.username_for(user)}. Every statement is recorded."
      run_loop
    rescue Error, Interrupt => e
      @output.puts(e.message.presence || "Cancelled.")
    ensure
      Console1984.session_logger.finish_session
      @connection_pool&.disconnect!
    end

    private

    def run_loop
      while (text = read_statement)
        text = text.strip
        next if text.empty?
        break if QUIT_COMMANDS.include?(text.delete_suffix(";"))

        execute(text)
      end
    end

    def execute(text)
      sql = expand(text)
      Console1984.session_logger.before_executing([text == sql ? sql : "#{text}\n#{sql}"])
      if sql.match?(protected_tables_pattern)
        @output.puts "Refused: the audit tables cannot be read or changed from this console."
        return
      end

      print_result(connection.raw_connection.async_exec(sql))
    rescue PG::Error, ActiveRecord::ActiveRecordError => e
      @output.puts e.message
    end

    # psql-style shortcuts, written out as SQL so the audit shows what ran.
    def expand(text)
      case text
      when "\\dt" then LIST_TABLES_SQL
      when /\A\\d\s+([\w.]+)\z/
        table = connection.quote(Regexp.last_match(1))
        "SELECT column_name, data_type, is_nullable FROM information_schema.columns " \
          "WHERE table_schema = current_schema() AND table_name = #{table} ORDER BY ordinal_position"
      else text
      end
    end

    def print_result(result)
      if result.nfields.zero?
        @output.puts result.cmd_status
        return
      end

      rows = result.values.map { |row| row.map { |value| format_cell(value) } }
      widths = result.fields.each_with_index.map { |field, i| ([field] + rows.map { it[i] }).map(&:length).max }
      @output.puts format_row(result.fields, widths)
      @output.puts widths.map { "-" * it }.join("-+-")
      rows.each { @output.puts format_row(it, widths) }
      @output.puts "(#{result.ntuples} #{"row".pluralize(result.ntuples)})"
    end

    def format_row(values, widths) = values.each_with_index.map { |value, i| value.ljust(widths[i]) }.join(" | ")

    def format_cell(value)
      text = value.nil? ? "NULL" : value.to_s.gsub(/\s+/, " ")
      text.length > MAX_CELL_WIDTH ? "#{text.first(MAX_CELL_WIDTH - 1)}…" : text
    end

    def read_reason
      reason = @input.call("Why do you need the SQL console? ", single_line: true).to_s.strip
      raise Error, "A reason is required." if reason.empty?

      reason
    end

    def read_statement = @input.call(PROMPT, single_line: false)

    # A statement ends at a semicolon. A backslash command or a quit command
    # ends at the end of its line.
    def read_with_reline(prompt, single_line:)
      require "reline"
      return Reline.readline(prompt, true) if single_line

      Reline.readmultiline(prompt, true) do |text|
        stripped = text.strip
        stripped.empty? || stripped.end_with?(";") || stripped.start_with?("\\") || QUIT_COMMANDS.include?(stripped)
      end
    end

    # The Console1984 tables, this app's console access requests and the
    # Audits1984 reviews. Console1984 blocks the same tables in the Rails
    # console.
    def protected_tables_pattern
      @protected_tables_pattern ||= begin
        tables = [Console1984::Session, Console1984::User, Console1984::Command, Console1984::SensitiveAccess,
                  ConsoleAccessRequest, Audits1984::Audit].map(&:table_name)
        Regexp.new(tables.map { Regexp.escape(it) }.join("|"), Regexp::IGNORECASE)
      end
    end

    def connection = connection_pool.lease_connection

    def connection_pool
      @connection_pool ||= ActiveRecord::Base.connection_handler.establish_connection(
        @db_config, owner_name: "ConsoleAccess::SqlConsole"
      )
    end

  end
end
