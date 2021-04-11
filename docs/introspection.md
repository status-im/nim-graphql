### Introspection

You can use introspection at any time using these metafields:

```graphql
__schema: __Schema!
__type(name: String!): __Type
__typename: String!
```

## Introspection API

The schema of the GraphQL schema introspection system:

```graphql
type __Schema {
  description: String
  types(includeBuiltin: Boolean = false): [__Type!]!
  queryType: __Type!
  mutationType: __Type
  subscriptionType: __Type
  directives(includeBuiltin: Boolean = false): [__Directive!]!
}

type __Type {
  kind: __TypeKind!
  name: String
  description: String

  # should be non-null for OBJECT and INTERFACE only, must be null for the others
  fields(includeDeprecated: Boolean = false): [__Field!]

  # should be non-null for OBJECT and INTERFACE only, must be null for the others
  interfaces: [__Type!]

  # should be non-null for INTERFACE and UNION only, always null for the others
  possibleTypes: [__Type!]

  # should be non-null for ENUM only, must be null for the others
  enumValues(includeDeprecated: Boolean = false): [__EnumValue!]

  # should be non-null for INPUT_OBJECT only, must be null for the others
  inputFields: [__InputValue!]

  # should be non-null for NON_NULL and LIST only, must be null for the others
  ofType: __Type

  # should be non-null for custom SCALAR only, must be null for the others
  specifiedBy: String
}

type __Field {
  name: String!
  description: String
  args: [__InputValue!]!
  type: __Type!
  isDeprecated: Boolean!
  deprecationReason: String
}

type __InputValue {
  name: String!
  description: String
  type: __Type!
  defaultValue: String
}

type __EnumValue {
  name: String!
  description: String
  isDeprecated: Boolean!
  deprecationReason: String
}

enum __TypeKind {
  SCALAR
  OBJECT
  INTERFACE
  UNION
  ENUM
  INPUT_OBJECT
  LIST
  NON_NULL
}

type __Directive {
  name: String!
  description: String
  locations: [__DirectiveLocation!]!
  args: [__InputValue!]!
  isRepeatable: Boolean!
}

enum __DirectiveLocation {
  QUERY
  MUTATION
  SUBSCRIPTION
  FIELD
  FRAGMENT_DEFINITION
  FRAGMENT_SPREAD
  INLINE_FRAGMENT
  VARIABLE_DEFINITION
  SCHEMA
  SCALAR
  OBJECT
  FIELD_DEFINITION
  ARGUMENT_DEFINITION
  INTERFACE
  UNION
  ENUM
  ENUM_VALUE
  INPUT_OBJECT
  INPUT_FIELD_DEFINITION
}
```

## Non-standard features

You may have noticed that two fields of `__Schema` contains `includeBuiltin` parameter.
If this parameter value is true, you will get builtin types and your own defined types.
But if the parameter value is false, you will get only your own types.

```graphql
  types(includeBuiltin: Boolean = false): [__Type!]!
  directives(includeBuiltin: Boolean = false): [__Directive!]!
```
