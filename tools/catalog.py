"""Catálogo de personagens do KelwinSouls: papel na lore, tamanho no jogo e orçamento de polígonos.

height_m  = altura final no jogo (o modelo é reescalado para isso)
tris      = alvo de triângulos depois da simplificação (Intel Iris Xe → orçamento modesto)
role      = player | boss | elite | enemy | dragon | npc
"""

CATALOG = {
    # --- Ordem de Marfim (cavaleiros caídos do Anel de Marfim) ---
    "aurencast__the_ivory_oathkeeper": dict(title="Aurencast, o Guardião do Juramento", role="boss", region="cidadela_marfim", height_m=3.2, tris=60000),
    "astravyne__the_ivory_bloodlancer": dict(title="Astravyne, a Lanceira de Sangue", role="elite", region="cidadela_marfim", height_m=2.4, tris=45000),
    "drakvald__the_ivory_dreadmarshal": dict(title="Drakvald, o Marechal do Pavor", role="elite", region="cidadela_marfim", height_m=2.6, tris=45000),
    "ivorae__the_faceless_queen": dict(title="Ivorae, a Rainha sem Rosto", role="boss", region="cidadela_marfim", height_m=4.0, tris=60000),
    # --- Cinzas e Forja Infernal ---
    "rhaum__the_hellforged_colossus": dict(title="Rhaum, o Colosso Forjado no Inferno", role="boss", region="fornalha", height_m=7.0, tris=60000),
    "hellforged_behemoth__the_infernal_titan": dict(title="O Titã Infernal", role="boss", region="fornalha", height_m=8.0, tris=60000),
    "gorthazul__the_ashhorn_behemoth": dict(title="Gorthazul, o Beemote Chifre-de-Cinza", role="elite", region="fornalha", height_m=5.0, tris=45000),
    "vormak__the_ashen_headsman": dict(title="Vormak, o Carrasco Cinzento", role="boss", region="fornalha", height_m=3.0, tris=60000),
    "volcanic_obsidian_golem_creature": dict(title="Golem de Obsidiana Vulcânica", role="elite", region="fornalha", height_m=5.5, tris=45000),
    # --- Obsidiana ---
    "nexmora__the_obsidian_matriarch": dict(title="Nexmora, a Matriarca de Obsidiana", role="boss", region="abismo_obsidiana", height_m=3.6, tris=60000),
    "varkhen__the_obsidian_oathbreaker": dict(title="Varkhen, o Quebra-Juramentos", role="elite", region="abismo_obsidiana", height_m=2.5, tris=45000),
    # --- Gelo ---
    "sylvaris__the_frostveil_duelist": dict(title="Sylvaris, a Duelista do Véu Gélido", role="elite", region="picos_gelidos", height_m=2.2, tris=45000),
    "veltharion__the_frostbound_cavalier": dict(title="Veltharion, o Cavaleiro Congelado", role="boss", region="picos_gelidos", height_m=3.4, tris=50000),
    # --- Sangue e Espinhos ---
    "ravenkor__the_bloodsteel_duelist": dict(title="Ravenkor, o Maculado de Aço-Sangue", role="player", region="todas", height_m=2.0, tris=50000),
    "zarakhul__the_bloodthorn_centaur": dict(title="Zarakhul, o Centauro Espinho-Sangrento", role="boss", region="pantano_espinhos", height_m=3.8, tris=60000),
    "morvessa__the_thorn_matriarch": dict(title="Morvessa, a Matriarca dos Espinhos", role="boss", region="pantano_espinhos", height_m=4.5, tris=60000),
    # --- Cemitério e Mortos ---
    "osskaroth__the_boneheap_revenant": dict(title="Osskaroth, o Revenante do Ossuário", role="boss", region="cemiterio", height_m=4.5, tris=60000),
    "gravestone_golem_-_cemetery_guardian": dict(title="Golem Lápide, Guardião do Cemitério", role="elite", region="cemiterio", height_m=4.0, tris=45000),
    # --- Fé e Véus ---
    "the_holy_rider__mounted_crusader": dict(title="O Cavaleiro Sagrado", role="elite", region="vale_inicial", height_m=3.2, tris=50000),
    "sister_vesper__the_veiled_oath": dict(title="Irmã Vesper do Juramento Velado", role="npc", region="vale_inicial", height_m=1.9, tris=40000),
    "vaelrith__the_veiled_horn": dict(title="Vaelrith, o Chifre Velado", role="enemy", region="vale_inicial", height_m=2.2, tris=35000),
    # --- Oriente Carmesim ---
    "zhenkar__the_crimson_oni_shogun": dict(title="Zhenkar, o Xogum Oni Carmesim", role="boss", region="pagode_carmesim", height_m=3.0, tris=60000),
    # --- Criaturas animadas ---
    "gastaroid_queen": dict(title="Rainha Gastaroide", role="boss", region="pantano_espinhos", height_m=5.0, tris=0, animated=True),
    "red_dragon": dict(title="Kelvhar, o Dragão Rubro", role="dragon", region="fornalha", height_m=9.0, tris=0, animated=True),
    "drogon_-_dragon_game_of_thrones": dict(title="O Dragão Ancestral", role="dragon", region="picos_gelidos", height_m=12.0, tris=0, animated=True,
                                            note="Asset de Game of Thrones (HBO): só para uso pessoal, não distribuir."),
}
