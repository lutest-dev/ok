export type Stats = {
	hp: number,
	attack: number,
	defense: number,
	special_attack: number,
	special_defense: number,
	speed: number,
}

export type Pokemon = {
	id: number,
	name: string,
	types: { string },
	height: number,
	weight: number,
	abilities: { string },
	stats: Stats,
	evolutions: { { string } },
	sprite_url: string?,
	shiny_sprite_url: string?,
}

export type PokeApiError = 'not_found' | 'request_failed' | 'invalid_response'

export type Request = (url: string) -> any

export type PokeApi = {
	get: (name: string) -> (Pokemon?, PokeApiError?),
}

export type SearchError = PokeApiError | 'invalid_query'

export type Callback = (Pokemon?, SearchError?) -> ()

export type Get = (name: string) -> (Pokemon?, PokeApiError?)

export type Search = {
	query: (text: string, callback: Callback) -> (),
}

return nil
