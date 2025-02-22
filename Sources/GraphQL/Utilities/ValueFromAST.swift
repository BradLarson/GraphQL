import OrderedCollections

/**
 * Produces a Map value given a GraphQL Value AST.
 *
 * A GraphQL type must be provided, which will be used to interpret different
 * GraphQL Value literals.
 *
 * | GraphQL Value        | Map Value     |
 * | -------------------- | ------------- |
 * | Input Object         | .dictionary   |
 * | List                 | .array        |
 * | Boolean              | .bool         |
 * | String               | .string       |
 * | Int                  | .int          |
 * | Float                | .float        |
 * | Enum Value           | .string       |
 *
 */
func valueFromAST(valueAST: Value, type: GraphQLInputType, variables: [String: Map] = [:]) throws -> Map {
    if let nonNullType = type as? GraphQLNonNull {
        // Note: we're not checking that the result of valueFromAST is non-null.
        // We're assuming that this query has been validated and the value used
        // here is of the correct type.
        return try valueFromAST(valueAST: valueAST, type: nonNullType.ofType as! GraphQLInputType, variables: variables)
    }

    if let variable = valueAST as? Variable {
        let variableName = variable.name.value

        //    if (!variables || !variables.hasOwnProperty(variableName)) {
        //      return null;
        //    }
        // Note: we're not doing any checking that this variable is correct. We're
        // assuming that this query has been validated and the variable usage here
        // is of the correct type.
        if let variable = variables[variableName] {
            return variable
        } else {
            return .null
        }
    }

    if let list = type as? GraphQLList {
        let itemType = list.ofType

        if let listValue = valueAST as? ListValue {
            return try .array(listValue.values.map({
                try valueFromAST(
                    valueAST: $0,
                    type: itemType as! GraphQLInputType,
                    variables: variables
                )
            }))
        }

        return try [valueFromAST(valueAST: valueAST, type: itemType as! GraphQLInputType, variables: variables)]
    }

    if let objectType = type as? GraphQLInputObjectType {
        guard let objectValue = valueAST as? ObjectValue else {
            throw GraphQLError(message: "Must be object type")
        }

        let fields = objectType.fields
        let fieldASTs = objectValue.fields.keyMap({ $0.name.value })

        return try .dictionary(fields.keys.reduce(OrderedDictionary<String, Map>()) { obj, fieldName in
            var obj = obj
            let field = fields[fieldName]!
            if let fieldAST = fieldASTs[fieldName] {
                let fieldValue = try valueFromAST(
                    valueAST: fieldAST.value,
                    type: field.type,
                    variables: variables
                )
                obj[fieldName] = fieldValue
            } else {
                // If AST doesn't contain field, it is undefined
                if let defaultValue = field.defaultValue {
                    obj[fieldName] = defaultValue
                } else {
                    obj[fieldName] = .undefined
                }
            }
            
            return obj
        })
    }
    
    guard let type = type as? GraphQLLeafType else {
        throw GraphQLError(message: "Must be leaf type")
    }
    
    // If we've made it this far, it should be a literal
    return try type.parseLiteral(valueAST: valueAST)
}
