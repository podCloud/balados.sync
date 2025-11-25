Ce projet a été généré par Claude et copié collé dans des fichiers à partir de cette note et d'une discussion pour affiner les résultats :

- En Elixir ?
	- DB a part ala balados
		- Event sourcing
		- events
			- id
			- timestamp
			- user
			- type (subscribe, unsubscribe, play, position, save, share, privacy, remove, sync)
			- object {rss_source_feed, rss_source_id} // null
			- data {} // {privacy: (public|anonymous|private)
		- Changement de privacy :
			- on maj public_events pour retirer/remettre les events de l'user ( + feed si applicable)
		- Remove :
			- on maj public_events pour retirer les events de l'user + feed (+ item si applicable)
			- on manipule events pour supprimer les events en vrai
			- on snapshot l'utilisateur
		- Sync
			- on émet des événements pour chaque diff
			- subscriptions
				- si sub_id inconnu on émet `subscribe`
				- si sub_id connu
					- si synced subscribed (subscribed_at > unsubscribed_at)
						- si nous aussi déjà server subscribed
							- si synced subscribed_at > server subscribed_at
								- on émet `subscribe` (pour maj les dates et la source de l'info)
						- si pas encore server subscribed
							- si synced subscribed_at > server unsubscribed_at
								- on émet `subscribe`
					- si synced unsubscribed (unsubscribed_at > subscribed_at)
						- si server unsubscribed
							- si synced unsubscribed_at > server unsubscribed_at
								- on émet `unsubscribe` pour maj les dates
						- si server subscribed
							- si synced unsubscribed_at > server subscribed_at
								- on émet `unsubscribe`
			- playlists
				- TODO Il faut ajouter des playlist items avec des dates d'ajout et suppr
			- play_statuses
				- on prends simplement tout ce qui est updated_at plus récent que sur notre serveur
					- on émet des events `play`
			- evenements
				- Taches type privacy, remove
			- Finalement on snapshot l'utilisateur une fois qu'on est sur que tout ça est bien déroulé.
				- TODO il faut probablement que l'event snapshot déclenche un effet de bord qui :
					- récupère les datas dans les tables de projection
					- Emit un nouvel event checkpoint avec ces datas
					- Le nouvel event mets a jour les datas si nécessaire. Un event checkpoint est considéré comme source de vérité, les opérations sont des upsert
		- Projections
			- public_events
				- Globalement events filtré par privacy
			- podcast_popularity / episode_popularity
				- rss_source_feed
				- rss_source_item
				- feed/episode_title
				- feed/episode_author
				- feed/episode_description
				- feed/episode_cover
					- src
					- srcset
				- plays: int
				- plays_people: recent public users who played
				- likes: int
				- likes_people: recent public users who liked
			- subscriptions
				- id
				- rss_feed_title
				- rss_source_feed
				- subscribed_at
				- unsubscribed_at
				- created_at
			- play_statuses
				- rss_source
				- rss_feed_title
				- rss_item_title
				- rss_enclosure
					- duration
					- size
					- cover
						- src
						- srcset
				- played (true/false)
				- position
				- updated_at
			- playlists
				- id
				- name
				- description
				- updated_at
				- items
					- item_id
					- item_title
					- feed_title
					- rss_source
					- created_at
					- updated_at
					- deleted_at
			- Toutes les 15 minutes, on récupère la liste des events de plus de 45j. On créé un snapshot des états liés aux événements de chaque user et on émet un checkpoint :
				- L'objet est le suivant :
				-
				  ```yaml
				  event_user: user
				  event_type: snapshot
				  event_object: null
				  event_data:
				    playlists:
				      - playlist_id: id
				        playlist_name: name
				        ...
				      - ...
				    play_statuses:
				      - rss_source: ...
				        played: ...
				      - ...
				  ```
				- Le checkpoint ne contient pas les éléments qui ont un deleted_at > 45j ou un unsubscribed_at > subscribed_at > 45j
			- Ce checkpoint mets à jour toutes les projections associées
				- Pour chaque flux on créé un event roll_stats qui va juste recalculer la popularité du podcast associé avec la même fonction de projection de chaque event play etc.
				- Ensuite, via un paramètre dans l'évent de snapshot retransmis à checkpoint on déclenche un effet de bord qui supprime tous les évènements qui ont plus de 31j
