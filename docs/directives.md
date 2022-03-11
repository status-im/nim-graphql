## Directives

Current implementation provides 4 builtin directives.

### Builtin directives

```graphql
directive @skip(
  if: Boolean!
) on FIELD | FRAGMENT_SPREAD | INLINE_FRAGMENT

directive @include(
  if: Boolean!
) on FIELD | FRAGMENT_SPREAD | INLINE_FRAGMENT

directive @deprecated(
  reason: String = "No longer supported"
) on FIELD_DEFINITION | ENUM_VALUE | ARGUMENT_DEFINITION | INPUT_FIELD_DEFINITION

directive @specifiedByURL(
  url: String!
) on SCALAR
```

### Custom directives

Currently there is no interface provided to implement custom directives.
We are still looking for best design for custom directives.
