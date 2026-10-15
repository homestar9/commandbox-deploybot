/**
 * Configures the commandbox-deploybot CommandBox module.
 *
 * This module adds CommandBox commands that start with `deploybot`. Examples are
 * `box deploybot token set`, `box deploybot env check`, and `box deploybot env push`. Files in
 * commands/deploybot receive command input. Files in models/ do the work.
 *
 * The mapping and model namespace always use the package slug. The names stay the same when
 * the module comes from ForgeBox or when the tests load this working copy.
 */
component {

	this.title          = "commandbox-deploybot";
	this.cfmapping      = "commandbox-deploybot";
	this.modelNamespace = "commandbox-deploybot";
	this.autoMapModels  = true;

	function configure(){
		settings = {};
	}
}
