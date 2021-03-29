schema {
	mutation: mutationType
	query: queryType
	subscription: subscriptionType
}
scalar Date
type Android {
	primaryFunction: String!
}
type subscriptionType {
	starships: [Starship!]!
}
enum Series {
	TheOriginalSeries,
	TheNextGeneration,
	DeepSpaceNine,
	Voyager,
	Enterprise,
	Discovery,
}
input Input {
	first: Int!
	after: String
}
type Starship {
	series: [Series]!
	id: Int!
	commander: Character!
	name: String!
	size: Float!
	crew: [Character!]!
	designation: String!
}
# note: nestedness of type 'Starship' not determined; output may be suboptimal
input StarshipIn {
	series: [Series]!
	id: Int!
	commander: CharacterIn!
	name: String!
	size: Float!
	crew: [CharacterIn!]!
	designation: String!
}
input AddCrewmanData {
	shipId: Int!
	series: [Series!]!
	name: String!
}
interface Character {
	ships: Starship
	series: [Series!]!
	id: Int!
	ship: Starship
	name: String!
	allwaysNull: Starship
	commands: [Character!]!
	alsoAllwaysNull: Int
	commanders: [Character!]!
}
# note: nestedness of type 'Character' not determined; output may be suboptimal
input CharacterIn {
	ships: StarshipIn
	series: [Series!]!
	id: Int!
	ship: StarshipIn
	name: String!
	allwaysNull: StarshipIn
	commands: [CharacterIn!]!
	alsoAllwaysNull: Int
	commanders: [CharacterIn!]!
}
type mutationType {
	getStupidestCrewman: Character!
	addCrewman(input: AddCrewmanData!): Character!
}
type queryType {
	shipsselection(ids: [Int!]!): [Starship!]!
	currentTime: DateTime!
	starships(overSize: Float!): [Starship!]!
	captain(series: Series!): Character!
	humanoids: [Humanoid!]!
	starship(id: Int!): Starship
	androids: [Android!]!
	resolverWillThrow: [Android!]!
	numberBetween(searchInput: Input!): Starship!
	search(name: String!): SearchResult!
	starshipDoesNotExist: Starship!
	character(id: Int!): Character
}
type Humanoid {
	dateOfBirth: Date!
	species: String!
}
scalar SearchResult
scalar DateTime
