# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

# This document describe builtin types/schema available during
# runtime execution

# Builtin directives

"Builtin @skip directive"
directive @skip(
  if: Boolean!
) on FIELD | FRAGMENT_SPREAD | INLINE_FRAGMENT

"Builtin @include directive"
directive @include(
  if: Boolean!
) on FIELD | FRAGMENT_SPREAD | INLINE_FRAGMENT

"Builtin @deprecated directive"
directive @deprecated(
  reason: String = "No longer supported"
) on FIELD_DEFINITION | ENUM_VALUE

# Builtin scalars
"Builtin `Int` scalar"
scalar Int

"Builtin `Float` scalar"
scalar Float

"Builtin `String` scalar"
scalar String

"Builtin `Boolean` scalar"
scalar Boolean

"Builtin `ID` scalar"
scalar ID

# special parent type for instrospection
"__Query is special introspection parent type"
type __Query {
  __schema: __Schema!
  __type(name: String!): __Type
  __typename: String!
}

" Builtin __Schema type"
type __Schema {
  description: String
  types(includeBuiltin: Boolean = false): [__Type!]!
  queryType: __Type!
  mutationType: __Type
  subscriptionType: __Type
  directives(includeBuiltin: Boolean = false): [__Directive!]!
}

"Builtin __Type type"
type __Type {
  kind: __TypeKind!

  "should be null for NON_NULL and LIST only, must be non-null for the others"
  name: String

  "get the type's description"
  description: String

  "should be non-null for OBJECT and INTERFACE only, must be null for the others"
  fields(includeDeprecated: Boolean = false): [__Field!]

  "should be non-null for OBJECT and INTERFACE only, must be null for the others"
  interfaces: [__Type!]

  "should be non-null for INTERFACE and UNION only, always null for the others"
  possibleTypes: [__Type!]

  "should be non-null for ENUM only, must be null for the others"
  enumValues(includeDeprecated: Boolean = false): [__EnumValue!]

  "should be non-null for INPUT_OBJECT only, must be null for the others"
  inputFields: [__InputValue!]

  "should be non-null for NON_NULL and LIST only, must be null for the others"
  ofType: __Type
}

" Builtin __Field type"
type __Field {
  name: String!
  description: String
  args: [__InputValue!]!
  type: __Type!
  isDeprecated: Boolean!
  deprecationReason: String
}

"Builtin __InputValue type"
type __InputValue {
  name: String!
  description: String
  type: __Type!
  defaultValue: String
}

"Builtin __EnumValue type"
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

"Builtin __Directive type"
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
