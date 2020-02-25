//
//  ManagedImporter.swift
//  InAndOut
//
//  Created by Ben Gottlieb on 2/24/20.
//  Copyright © 2020 Stand Alone, Inc. All rights reserved.
//

import CoreData
import ZIPFoundation

public class ManagedImporter {
	public enum ImportError: Error { case noJSONFileFound, improperJSONFormatting, missingEntityList, missingObjectID }
	let context: NSManagedObjectContext
	
	var importedRecords: [String: NSManagedObjectID] = [:]
	init(context: NSManagedObjectContext) {
		self.context = context
	}
	
	public func `import`(from url: URL, checkingForDuplicates: Bool = false) throws {
		if url.pathExtension == "zip" {
			let dest = url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent + "_unzipped")
			try FileManager.default.unzipItem(at: url, to: dest)
			try self.importJSON(from: dest.appendingPathComponent(ManagedExporter.jsonFilename), checkingForDuplicates: checkingForDuplicates)
			try? FileManager.default.removeItem(at: dest)
		} else {
			try self.importJSON(from: url.appendingPathComponent(ManagedExporter.jsonFilename), checkingForDuplicates: checkingForDuplicates)
		}
	}

	func importJSON(from url: URL, checkingForDuplicates: Bool = false) throws {
		guard FileManager.default.fileExists(at: url) else { throw ImportError.noJSONFileFound }
		let data = try Data(contentsOf: url)
		guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else { throw ImportError.improperJSONFormatting }
		guard let entityList = json[ManagedExporter.entityNameListKey] as? [String] else { throw ImportError.missingEntityList }
		var pendingLinks: [PendingRelationship] = []
		let parent = url.deletingLastPathComponent()
		
		for entityName in entityList {
			guard let recordDicts = json[entityName] as? [[String: Any]] else { continue }
			
			//let current = checkingForDuplicates ? self.context.fetchAll(named: entityName).compactMap { try? $0.recordPropertiesAsDictionary(dataSizeLimit: nil, storingDataAt: nil) } : []
			for recordDict in recordDicts {
				let newObject = self.context.insertEntity(named: entityName)
				do {
					let result = try newObject.import(from: recordDict, basedAt: parent)
					if !result.relationships.isEmpty { pendingLinks += result.relationships }
					self.importedRecords[result.original] = result.objectID
				} catch {
					print("Error importing object: \(error)")
				}
			}
		}
		
		for relationship in pendingLinks {
			let fromRecord = self.context.object(with: relationship.fromID)
			guard  let id = self.importedRecords[relationship.toID] else { continue }
			let toRecord = self.context.object(with: id)
			fromRecord.setValue(toRecord, forKey: relationship.name)
		}
		
		try self.context.save()
	}
	
	struct PendingRelationship {
		let fromID: NSManagedObjectID
		let toID: String
		let name: String
	}
	
	struct ImportResult {
		let relationships: [PendingRelationship]
		let objectID: NSManagedObjectID
		let original: String
	}
}

extension NSManagedObject {
	func `import`(from dict: [String: Any], basedAt url: URL?) throws -> ManagedImporter.ImportResult {
		var pending: [ManagedImporter.PendingRelationship] = []
		
		guard let originalID = dict[NSManagedObject.jsonObjectIDKey] as? String else { throw ManagedImporter.ImportError.missingObjectID}
		for (key, value) in dict {
			if let info = value as? [String: Any] {
				if let dataFilename = info["data"] as? String, let dataURL = url?.appendingPathComponent(dataFilename) {
					let data = try Data(contentsOf: dataURL)
					self.setValue(data, forKey: key)
				} else if let idURL = info["record_id"] as? String {
					pending.append(ManagedImporter.PendingRelationship(fromID: self.objectID, toID: idURL, name: key))
				}
			} else if let prop = self.entity.attributesByName[key] {
				switch prop.attributeType {
				case .booleanAttributeType:
					self.setValue(value as? Bool ?? false, forKey: key)
					
				case .stringAttributeType, .decimalAttributeType, .doubleAttributeType, .floatAttributeType, .integer16AttributeType, .integer32AttributeType, .integer64AttributeType:
					self.setValue(value, forKey: key)

				case .UUIDAttributeType:
					if let string = value as? String { self.setValue(UUID(uuidString: string), forKey: key) }
					
				case .URIAttributeType:
					if let string = value as? String { self.setValue(URL(string: string), forKey: key) }

				case .dateAttributeType:
					if let string = value as? String { self.setValue(NSManagedObject.dateJSONFormater.date(from: string), forKey: key) }
					
				case .binaryDataAttributeType:
					if let string = value as? String { self.setValue(Data(base64Encoded: string), forKey: key) }
					default: break
				}
			}
		}
		
		return ManagedImporter.ImportResult(relationships: pending, objectID: self.objectID, original: originalID)
	}
}


