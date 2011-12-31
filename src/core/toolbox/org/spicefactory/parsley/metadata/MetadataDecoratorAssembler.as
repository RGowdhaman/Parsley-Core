/*
 * Copyright 2008-2009 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.spicefactory.parsley.metadata {

import org.spicefactory.lib.errors.IllegalStateError;
import org.spicefactory.lib.reflect.ClassInfo;
import org.spicefactory.lib.reflect.Converters;
import org.spicefactory.lib.reflect.Member;
import org.spicefactory.lib.reflect.Metadata;
import org.spicefactory.lib.reflect.MetadataAware;
import org.spicefactory.lib.reflect.Method;
import org.spicefactory.lib.reflect.Property;
import org.spicefactory.lib.reflect.metadata.Target;
import org.spicefactory.parsley.asconfig.metadata.DynamicObjectDefinitionMetadata;
import org.spicefactory.parsley.asconfig.metadata.InternalProperty;
import org.spicefactory.parsley.asconfig.metadata.ObjectDefinitionMetadata;
import org.spicefactory.parsley.comobserver.tag.CommandCompleteDecorator;
import org.spicefactory.parsley.comobserver.tag.CommandErrorDecorator;
import org.spicefactory.parsley.comobserver.tag.CommandResultDecorator;
import org.spicefactory.parsley.comobserver.tag.CommandStatusDecorator;
import org.spicefactory.parsley.core.builder.DecoratorAssembler;
import org.spicefactory.parsley.core.builder.ObjectDefinitionDecorator;
import org.spicefactory.parsley.core.errors.ContextError;
import org.spicefactory.parsley.core.messaging.impl.Selector;
import org.spicefactory.parsley.core.processor.Phase;
import org.spicefactory.parsley.core.view.metadata.Autoremove;
import org.spicefactory.parsley.inject.tag.InjectConstructorDecorator;
import org.spicefactory.parsley.inject.tag.InjectMethodDecorator;
import org.spicefactory.parsley.inject.tag.InjectPropertyDecorator;
import org.spicefactory.parsley.lifecycle.tag.AsyncInitDecorator;
import org.spicefactory.parsley.lifecycle.tag.DestroyMethodDecorator;
import org.spicefactory.parsley.lifecycle.tag.FactoryMethodDecorator;
import org.spicefactory.parsley.lifecycle.tag.InitMethodDecorator;
import org.spicefactory.parsley.lifecycle.tag.ObserveMethodDecorator;
import org.spicefactory.parsley.messaging.tag.ManagedEventsDecorator;
import org.spicefactory.parsley.messaging.tag.MessageBindingDecorator;
import org.spicefactory.parsley.messaging.tag.MessageDispatcherDecorator;
import org.spicefactory.parsley.messaging.tag.MessageErrorDecorator;
import org.spicefactory.parsley.messaging.tag.MessageHandlerDecorator;
import org.spicefactory.parsley.resources.tag.ResourceBindingDecorator;

import flash.system.ApplicationDomain;
import flash.utils.Dictionary;



/**
 * DecoratorAssembler implementation that can be used by all object definition builders that wish to process
 * metadata tags on classes. All builtin configuration mechanisms (MXML, XML and ActionScript)
 * use this class per default. DecoratorAssemblers can be specified on an ObjectDefinitionRegistryFactory.
 * 
 * @author Jens Halm
 */
public class MetadataDecoratorAssembler implements DecoratorAssembler {
	
	
	private static const targetPropertyMap:Dictionary = new Dictionary();
	
	private static var initialized:Boolean = false;
	
	private static const metadataClasses:Array = [
	
		ProcessSuperclass,
		ProcessInterfaces,
	
		InjectConstructorDecorator,
		InjectPropertyDecorator,
		InjectMethodDecorator,
		
		FactoryMethodDecorator,
		InitMethodDecorator,
		DestroyMethodDecorator,
		ObserveMethodDecorator,
		AsyncInitDecorator,
		
		ManagedEventsDecorator,
		MessageDispatcherDecorator,
		MessageHandlerDecorator,
		MessageBindingDecorator,
		MessageErrorDecorator,

		CommandCompleteDecorator,
		CommandResultDecorator,
		CommandErrorDecorator,
		CommandStatusDecorator,
		
		ResourceBindingDecorator,
		
		Autoremove,

		Selector,
		Target,
		
		InternalProperty, // TODO - 3.0.M2 - move to ActionScriptContextBuilder
		ObjectDefinitionMetadata,
		DynamicObjectDefinitionMetadata
		
	];
	
	private static const replacements:Dictionary = new Dictionary();
	
	
	/**
	 * Initializes the metadata tag registrations for all builtin metadata tags.
	 * Will usually be called by the framework
	 * and does not need to be called by an application.
	 */
	public static function initialize () : void {
		if (initialized) return;
		initialized = true;
		
		for each (var metadataClass:Class in metadataClasses) {
			var typeToRegister:Class = (replacements[metadataClass] != null) ? replacements[metadataClass] : metadataClass;
			Metadata.registerMetadataClass(typeToRegister);
		}
		
		Converters.addConverter(Phase, new PhaseConverter());
	}
	
	/**
	 * Replaces one of the framework's builtin metadata tags with a custom one.
	 * Any previous replacements for the same type would get overwritten.
	 * This method must be called before starting to create the first Context of the application.
	 * 
	 * @param builtinTag the builtin tag that should be replaced
	 * @param replacement the actual replacement
	 */
	public static function replaceTag (builtinTag:Class, replacement:Class) : void {
		if (initialized) {
			throw new IllegalStateError("Builtin metadata tags have already been initialized");
		}
		replacements[builtinTag] = replacement;
	}

	/**
	 * Creates a new instance.
	 */
	function MetadataDecoratorAssembler () {
		initialize();
	}


	/**
	 * @inheritDoc
	 */	
	public function assemble (type:ClassInfo) : Array {
		var decorators:Array = new Array();
		var processed:ProcessedMembers = new ProcessedMembers();
		var oldDomain:ApplicationDomain = Converters.processingDomain;
		try {
			Converters.processingDomain = type.applicationDomain;
			doAssemble(type, decorators, processed);
		}
		finally {
			Converters.processingDomain = oldDomain;
		}
		return decorators;
	}
	
	private function doAssemble (type:ClassInfo, decorators:Array, processed:ProcessedMembers, classLevelOnly:Boolean = false) : void {
		extractMetadataDecorators(type, decorators);
		if (!classLevelOnly) {
			for each (var property:Property in type.getProperties()) {
				extractFromMember(property, decorators, processed);
			}
			for each (var method:Method in type.getMethods()) {
				extractFromMember(method, decorators, processed);
			}
		}
		if (type.hasMetadata(ProcessSuperclass)) {
			doAssemble(ClassInfo.forClass(type.getSuperClass(), type.applicationDomain), decorators, processed, true);
		}
		if (type.hasMetadata(ProcessInterfaces)) {
			for each (var ifType:Class in type.getInterfaces()) {
				doAssemble(ClassInfo.forClass(ifType, type.applicationDomain), decorators, processed);
			}
		}
	}
	
	private function extractFromMember (member:Member, decorators:Array, processed:ProcessedMembers = null) : void {
		if (processed.addMember(member)) {
			extractMetadataDecorators(member, decorators); 
		}
	}

	private function extractMetadataDecorators (type:MetadataAware, decorators:Array) : void {
		for each (var metadata:Object in type.getAllMetadata()) {
			if (metadata is ObjectDefinitionDecorator) {
				if (type is Member) {
					setTargetProperty(type as Member, metadata);
				}
				decorators.push(metadata);
			}
		}
	}
	
	private function setTargetProperty (member:Member, decorator:Object) : void {
		var ci:ClassInfo = ClassInfo.forInstance(decorator);
		var target:* = targetPropertyMap[ci.getClass()];
		if (target == undefined) {
			for each (var property:Property in ci.getProperties()) {
				if (property.getMetadata(Target).length > 0) {
					if (!property.writable) {
						target = new Error(property.toString() + " was marked with [Target] but is not writable");
					}
					else if (!property.type.isType(String)) {
						target = new Error(property.toString() + " was marked with [Target] but is not of type String");
					}
					else {
						target = property;
					}
					break; 
				}
			}
			if (target == null) {
				target = new Error("No property marked with [Target] in ObjectDefinitionDecorator class " + ci.name);
			}
			// we also cache errors so we do not process the same class twice
			targetPropertyMap[ci.getClass()] = target;
		}
		if (target is Property) {
			Property(target).setValue(decorator, member.name);
		}
		else {
			throw new ContextError(Error(target).message);
		}					
	}
}
}

import org.spicefactory.lib.errors.IllegalArgumentError;
import org.spicefactory.lib.reflect.Converter;
import org.spicefactory.lib.reflect.Member;
import org.spicefactory.parsley.core.processor.DestroyPhase;
import org.spicefactory.parsley.core.processor.InitPhase;

import flash.system.ApplicationDomain;
import flash.utils.Dictionary;

class ProcessedMembers {
	
	private var processed:Dictionary = new Dictionary();
	
	public function addMember (member:Member) : Boolean {
		var declared:String = (member.declaredBy == null) ? "" : member.declaredBy.name;
		var key:String = declared + "#" + member.name;
		if (processed[key]) return false;
		processed[key] = true;
		return true;
	}
	
}

class PhaseConverter implements Converter {


	public function convert (value: *, domain: ApplicationDomain = null): * {
		switch (value) {
			case "preInit": return InitPhase.preInit(int.MAX_VALUE);
			case "init": return InitPhase.init();
			case "postInit": return InitPhase.preInit(int.MIN_VALUE);
			case "preDestroy": return DestroyPhase.preDestroy(int.MAX_VALUE);
			case "destroy": return DestroyPhase.destroy();
			case "postDestroy": return DestroyPhase.postDestroy(int.MIN_VALUE);
			
			otherwise: throw new IllegalArgumentError("Not a valid constant for a phase: " + value);
		}
	}
	
}
