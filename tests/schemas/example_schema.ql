schema {
	mutation: mutationType
	query: queryType
	subscription: subscriptionType
}
type mutationType { _: Boolean }
type queryType {
	maybeNull: Int
	small: Small
	manysmall: [Small!]!
	neverNull: Int!
	foo: Int!
	bar: Int!
}
type subscriptionType { _: Boolean }
type Small {
	id: Int!
	foobar: [SmallChild!]!
	name: String!
	arg(a: Int!): [SmallChild!]!
}
input SmallIn {
	id: Int!
	foobar: [SmallChildIn!]!
	name: String!
}
type SmallChild {
	id: Int!
	name: String!
	foo(a: Int!): Int!
}
input SmallChildIn {
	id: Int!
	name: String!
}