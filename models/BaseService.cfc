/**
 * Provides shared tools for model components.
 *
 * A model component is not a CommandBox command. CommandBox does not automatically give it a
 * print buffer or shell. This base component gets those tools from WireBox. It also provides
 * printing helpers and the stop() function.
 *
 * Model components throw a Deploybot exception instead of calling error(). The command that
 * started the model converts that exception into a command error. This design lets tests use
 * model components without running a command.
 *
 * Models print key names and step summaries only. They never print file values or the token.
 */
component {

	property name="shell"   inject="shell";
	property name="print"   inject="PrintBuffer";
	property name="wirebox" inject="wirebox";

	/**
	 * Uses the caller's print buffer. Shared use keeps output from several components in order.
	 *
	 * @printer The CommandBox print buffer to use.
	 */
	function usePrinter( required any printer ){
		variables.print = arguments.printer;
		return this;
	}

	/**
	 * Creates another model component that uses the same print buffer.
	 *
	 * @name The component name, such as "TokenStore".
	 */
	function service( required string name ){
		return variables.wirebox.getInstance( arguments.name & "@commandbox-deploybot" ).usePrinter( variables.print );
	}

	/**
	 * Stops the model with a one-line message. The calling command reports the error.
	 *
	 * @message A description of the problem.
	 * @type    The exception type. Types that start with Deploybot. are shown without a stack trace.
	 */
	function stop( required string message, string type = "Deploybot.Stop" ){
		throw( type = arguments.type, message = arguments.message );
	}

	/**
	 * Prints detailed instructions and then stops the model with a one-line error.
	 *
	 * CommandBox error() removes line breaks from a message. This function prints the detailed
	 * instructions first so they keep their line breaks. It uses only the short summary for the
	 * final command error.
	 *
	 * @summary A one-line description of the problem.
	 * @detail  The instruction lines to print before the error.
	 * @heading A short heading for the instructions.
	 * @type    The exception type.
	 */
	function fail( required string summary, array detail = [], string heading = "What to do", string type = "Deploybot.Stop" ){
		if ( arguments.detail.len() ) {
			say( "" );
			variables.print.boldLine( arguments.heading & ":" ).toConsole();
			for ( var line in arguments.detail ) {
				variables.print.yellowLine( "  " & line ).toConsole();
			}
			say( "" );
		}
		return stop( arguments.summary, arguments.type );
	}

	/**
	 * Prints one plain line.
	 *
	 * @text The text to print.
	 */
	function say( required string text ){
		variables.print.line( arguments.text ).toConsole();
		return this;
	}

	/**
	 * Prints one green line for a good result.
	 *
	 * @text The text to print.
	 */
	function good( required string text ){
		variables.print.greenLine( arguments.text ).toConsole();
		return this;
	}

	/**
	 * Prints one yellow line for a warning.
	 *
	 * @text The text to print.
	 */
	function warn( required string text ){
		variables.print.yellowLine( arguments.text ).toConsole();
		return this;
	}

	/**
	 * Prints one red line for a problem.
	 *
	 * @text The text to print.
	 */
	function bad( required string text ){
		variables.print.redLine( arguments.text ).toConsole();
		return this;
	}

	/**
	 * Prints a bold heading line.
	 *
	 * @text The text to print.
	 */
	function heading( required string text ){
		variables.print.boldLine( arguments.text ).toConsole();
		return this;
	}
}
