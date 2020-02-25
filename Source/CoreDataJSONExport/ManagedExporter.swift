//
//  ManagedExporter.swift
//  InAndOut
//
//  Created by Ben Gottlieb on 2/24/20.
//  Copyright © 2020 Stand Alone, Inc. All rights reserved.
//

import CoreData
import ZIPFoundation
import Suite

public class ManagedExporter {
	let records: [NSManagedObject]
	let request: NSFetchRequest<NSManagedObject>?
	let context: NSManagedObjectContext!
	let entities: [NSEntityDescription]
	static let jsonFilename = "records.json"
	static let attachmentsDirectoryName = "attachments"
	static let entityNameListKey = "entity_names"
	
	public struct ExcludedFields {
		public var allEntities: [String] = []
		public var entityExclusions: [String: [String]] = [:]
		
		func excluded(for entity: String) -> [String] {
			return allEntities + (entityExclusions[entity] ?? [])
		}
		
		public init(_ base: [String]) {
			self.allEntities = base
		}
		
		public init() { }
	}
	
	public func export(to url: URL, excluding: ExcludedFields = ExcludedFields()) throws {
		try? FileManager.default.removeItem(at: url)
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
		var dict: [String: Any] = [:]
		let attachmentsURL = url.appendingPathComponent(ManagedExporter.attachmentsDirectoryName)
		try? FileManager.default.createDirectory(at: attachmentsURL, withIntermediateDirectories: true, attributes: nil)
		
		for entity in self.entities {
			guard let name = entity.name else { continue }
			var entityRecords: [[String: Any]] = []
			for record in try self.records(for: entity) {
				try entityRecords.append(record.exportAsDictionary(to: attachmentsURL, excluding: excluding.excluded(for: name)))
			}
			dict[name] = entityRecords
		}
		
		dict[ManagedExporter.entityNameListKey] = self.entities.compactMap { $0.name }
		let json = try JSONSerialization.data(withJSONObject: dict, options: [])
		try json.write(to: url.appendingPathComponent(ManagedExporter.jsonFilename))
	}
	
	public func export(toZip url: URL, excluding: ExcludedFields = ExcludedFields()) throws {
		let tempURL = FileManager.tempDirectory.appendingPathComponent(UUID().uuidString)
		defer { try? FileManager.default.removeItem(at: tempURL) }
		try self.export(to: tempURL, excluding: excluding)
		try FileManager.default.zipItem(at: tempURL, to: url, shouldKeepParent: false, compressionMethod: .deflate, progress: nil)
	}
	
	public init?(request: NSFetchRequest<NSManagedObject>? = nil, in context: NSManagedObjectContext) {
		self.records = []
		self.request = request
		self.context = context
		
		if let entity = request?.entity {
			self.entities = [entity]
		} else {
			self.entities = context.persistentStoreCoordinator?.managedObjectModel.entities ?? []
		}
		if self.entities.isEmpty { return nil }
	}
	
	public init?(records: [NSManagedObject]) {
		self.records = records
		self.request = nil
		self.entities = Array(Set(records.map { $0.entity }))

		guard let moc = records.first?.managedObjectContext else {
			self.context = nil
			return nil
		}
		self.context = moc
	}
	
	func records(for entity: NSEntityDescription) throws -> [NSManagedObject] {
		if let request = self.request {
			return try self.context.fetch(request)
		}
		
		if self.records.isEmpty {
			let request = NSFetchRequest<NSManagedObject>(entityName: entity.name!)
			return try self.context.fetch(request)
		}

		return self.records.filter { $0.entity == entity }
	}
	
}

extension NSManagedObject {
	static let dateJSONFormater: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
		return formatter
	}()
	static let jsonObjectIDKey = "_object_id_"
	
	func exportAsDictionary(to url: URL, dataSizeLimit: Int = 0, excluding: [String]) throws -> [String: Any] {
		var dict = try self.recordPropertiesAsDictionary(dataSizeLimit: dataSizeLimit, storingDataAt: url, excluding: excluding)
		
		for (name, relationship) in self.entity.relationshipsByName {
			guard !excluding.contains(name), !relationship.isToMany, let target = self.value(forKey: name) as? NSManagedObject, let destName = relationship.destinationEntity?.name else { continue }
			dict[name] = ["record_id": target.objectID.uriRepresentation().absoluteString, "entity": destName]
		}
		return dict
	}
	
	func recordPropertiesAsDictionary(dataSizeLimit: Int? = 0, storingDataAt url: URL?, excluding: [String]) throws -> [String: Any] {
		var dict: [String: Any] = [:]
		
		dict[NSManagedObject.jsonObjectIDKey] = self.objectID.uriRepresentation().absoluteString
		
		for (name, attr) in self.entity.attributesByName {
			guard !excluding.contains(name), let value = self.value(forKey: name) else { continue }
			switch attr.attributeType {
			case .booleanAttributeType:
				dict[name] = value as? Bool ?? false
				
			case .stringAttributeType, .decimalAttributeType, .doubleAttributeType, .floatAttributeType, .integer16AttributeType, .integer32AttributeType, .integer64AttributeType:
				dict[name] = value
				
			case .UUIDAttributeType:
				guard let uuid = value as? UUID else { continue }
				dict[name] = uuid.uuidString
				
			case .URIAttributeType:
				guard let url = value as? URL else { continue }
				dict[name] = url.absoluteString
				
			case .dateAttributeType:
				guard let date = value as? Date else { continue }
				dict[name] = NSManagedObject.dateJSONFormater.string(from: date)
				
			case .binaryDataAttributeType:
				guard let data = value as? Data else { continue }
				guard let limit = dataSizeLimit else {
					continue
				}
				if data.count > limit, let baseURL = url {
					let filename = UUID().uuidString + ".dat"
					let fileURL = baseURL.appendingPathComponent(filename)
					try data.write(to: fileURL)
					dict[name] = ["data": filename]
				} else {
					dict[name] = data.base64EncodedString()
				}
				
				default: break
			}
		}
		
		return dict
	}
}
