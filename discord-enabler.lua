-- Random MTG Card Spawner for Tabletop Simulator
-- version 3.0
backURL='https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/'
randomCardUrl = "https://api.scryfall.com/cards/random?q=lang:en&q=-t:land"
cardCounter = 300
debugMode = false

-- Cache settings
CACHE_SIZE = 2
cardCache = {}
cacheFilling = false
pendingFetches = 0

-- API throttling
lastRequestTime = 0
MIN_REQUEST_INTERVAL = 0.05  -- 50 milliseconds

headers = {
    ["User-Agent"] = "TabletopSimulator-DiscordEnabler/3.0",
    ["Accept"] = "application/json;q=0.9,*/*;q=0.8"
}

function throttledWebRequest(url, callback)
    local timeSinceLastRequest = os.time() - lastRequestTime
    local delay = math.max(0, MIN_REQUEST_INTERVAL - timeSinceLastRequest)
    
    local function makeRequest()
        WebRequest.custom(url, "GET", true, nil, headers, callback)
        lastRequestTime = os.time()
    end
    
    if delay > 0 then
        debugPrint("Throttling request: waiting " .. string.format("%.3f", delay) .. " seconds")
        Wait.time(makeRequest, delay)
    else
        makeRequest()
    end
end

-- Click the button to get a random card from Scryfall and spawn it
function onLoad()
    -- Create a button on the object
    self.createButton({
        tooltip="Get a random card",
        click_function="getRandomCard",
        function_owner=self,
        position={0, 0.1, 0},
        height=900,
        width=1200,
        color={0.1,0.1,0.1,0.85},
        hover_color={0.1,0.1,0.1,0.9}
    })
    
    -- Add context menu for debug mode
    self.addContextMenuItem("Toggle Debug Mode", toggleDebugMode)
    updateDebugModeMenu()
    
    -- Fill the cache
    fillCache()
end

function toggleDebugMode()
    debugMode = not debugMode
    updateDebugModeMenu()
    
    local status = debugMode and "enabled" or "disabled"
    printToAll("Debug mode " .. status, {r=1, g=1, b=0.2})
end

function updateDebugModeMenu()
    self.clearContextMenu()
    local menuText = debugMode and "Debug Mode: ON" or "Debug Mode: OFF"
    self.addContextMenuItem(menuText, toggleDebugMode)
end

-- Note there is a bug where if the button is clicked twice in quick succession,
-- the cache will only fill a single card then stall. On the next click it works
-- properly again.
function getRandomCard(obj, player)
    -- Check if cache has cards
    if #cardCache > 0 then
        local cachedCard = table.remove(cardCache, 1)
        debugPrint("Using cached card (" .. #cardCache .. " remaining in cache)")
        
        printToAll("Got card: " .. cachedCard.name, {r=0.2, g=1, b=0.2})
        
        -- Set the spawn position and rotation
        local position = self.getPosition()
        local rotation = self.getRotation()
        cachedCard.cardDat.Transform.posX = position.x + 2
        cachedCard.cardDat.Transform.posY = position.y + 2
        cachedCard.cardDat.Transform.posZ = position.z
        cachedCard.cardDat.Transform.rotX = rotation.x
        cachedCard.cardDat.Transform.rotY = rotation.y
        cachedCard.cardDat.Transform.rotZ = rotation.z

        spawnObjectData({data = cachedCard.cardDat})
        
        -- Refill cache asynchronously
        fillCache()
    else
        fetchAndSpawnCard()
    end
end

function fillCache()
    if cacheFilling then
        debugPrint("Cache already filling, skipping")
        return
    end
    
    local needed = CACHE_SIZE - #cardCache
    if needed <= 0 then
        debugPrint("Cache is full (" .. #cardCache .. "/" .. CACHE_SIZE .. ")")
        return
    end
    
    cacheFilling = true
    pendingFetches = needed
    debugPrint("Filling cache, need " .. needed .. " cards")
    
    Wait.time(fetchCardForCache, MIN_REQUEST_INTERVAL, needed)
end

function fetchCardForCache()    
    cardCounter = cardCounter + 1
    local currentCardNum = cardCounter
    
    debugPrint("Fetching card for cache (counter: " .. currentCardNum .. ")")
    
    throttledWebRequest(randomCardUrl, function(req)
        if req.is_error then
            debugPrint("Error fetching card for cache: " .. req.error_message)
            pendingFetches = pendingFetches - 1
            if pendingFetches <= 0 then
                cacheFilling = false
            end
            return
        end
        
        local c = JSONdecode(req.text)
        local cardName = c.name
        local cardDat = getCardDatFromJSON(c, currentCardNum)
        
        table.insert(cardCache, {name = cardName, cardDat = cardDat})
        debugPrint("Added '" .. cardName .. "' to cache (" .. #cardCache .. "/" .. CACHE_SIZE .. ")")
        
        pendingFetches = pendingFetches - 1
        if pendingFetches <= 0 then
            cacheFilling = false
            debugPrint("Cache filling complete")
        end
    end)
end

function fetchAndSpawnCard()
    local randomCardUrl = "https://api.scryfall.com/cards/random?q=lang:en&q=-t:land"
    
    printToAll("Fetching random card from Scryfall...", {r=0.2, g=0.8, b=1})
    
    cardCounter = cardCounter + 1
    local currentCardNum = cardCounter
    
    debugPrint("Direct fetch (counter: " .. currentCardNum .. ")")
   
    throttledWebRequest(randomCardUrl, function(req)
        if req.is_error then
            printToAll("Error fetching card: " .. req.error_message, {r=1, g=0.2, b=0.2})
            return
        end
        local c = JSONdecode(req.text)
        local cardName = c.name

        debugPrint("Received card: " .. cardName)
        debugPrint("Card type: " .. (c.type_line or "unknown"))

        local cardDat = getCardDatFromJSON(c, currentCardNum)

        printToAll("Got card: " .. cardName, {r=0.2, g=1, b=0.2})
        
        -- Set the spawn position and rotation
        local position = self.getPosition()
        local rotation = self.getRotation()
        cardDat.Transform.posX = position.x + 2
        cardDat.Transform.posY = position.y + 2
        cardDat.Transform.posZ = position.z
        cardDat.Transform.rotX = rotation.x
        cardDat.Transform.rotY = rotation.y
        cardDat.Transform.rotZ = rotation.z

        spawnObjectData({data = cardDat})
        
        -- Try to refill cache
        fillCache()
    end)
end


-- Copied this from 'Mystery Booster Generator' by pie

function getCardDatFromJSON(c,n)
  c.face=''
  c.oracle=''
  local qual='large'

  local imagesuffix=''
  if c.image_status~='highres_scan' then      -- cache buster for low quality images
    imagesuffix='?'..tostring(os.date("%x")):gsub('/', '')
  end

  --Check for card's spoiler image quality
  --Oracle text Handling for Split then DFC then Normal
  if c.card_faces and c.image_uris then
    for i,f in ipairs(c.card_faces) do
      if c.cmc then
        f.name=f.name:gsub('"','')..'\n'..f.type_line..' '..c.cmc..'CMC'
      else
        f.name=f.name:gsub('"','')..'\n'..f.type_line..' '..f.cmc..'CMC'
      end
      if i==1 then cardName=f.name end
      c.oracle=c.oracle..f.name..'\n'..setOracle(f)..(i==#c.card_faces and''or'\n')
    end
  elseif c.card_faces then
    local f=c.card_faces[1]
    if c.cmc then
      cardName=f.name:gsub('"','')..'\n'..f.type_line..' '..c.cmc..'CMC DFC'
    else
      cardName=f.name:gsub('"','')..'\n'..f.type_line..' '..f.cmc..'CMC DFC'
    end
    c.oracle=setOracle(f)
  else
    cardName=c.name:gsub('"','')..'\n'..c.type_line..' '..c.cmc..'CMC'
    c.oracle=setOracle(c)
  end
  local backDat=nil
  --Image Handling
  if c.card_faces and not c.image_uris then --DFC REWORKED for STATES!
    local faceAddress=c.card_faces[1].image_uris.normal:gsub('%?.*',''):gsub('normal',qual)..imagesuffix
    local backAddress=c.card_faces[2].image_uris.normal:gsub('%?.*',''):gsub('normal',qual)..imagesuffix
    if faceAddress:find('/back/') and backAddress:find('/front/') then
      local temp=faceAddress;faceAddress=backAddress;backAddress=temp
    end
    c.face=faceAddress
    local f=c.card_faces[2]
    local name
    if c.cmc then
      name=f.name:gsub('"','')..'\n'..f.type_line..' '..c.cmc..'CMC DFC'
    else
      name=f.name:gsub('"','')..'\n'..f.type_line..' '..f.cmc..'CMC DFC'
    end
    local oracle=setOracle(f)
    local b=n+100
    backDat={
      Transform={posX=0,posY=0,posZ=0,rotX=0,rotY=0,rotZ=0,scaleX=1,scaleY=1,scaleZ=1},
      Name="Card",
      Nickname=name,
      Description=oracle,
      Memo=c.oracle_id,
      CardID=b*100,
      CustomDeck={[b]={FaceURL=backAddress,BackURL=backURL,NumWidth=1,NumHeight=1,Type=0,BackIsHidden=true,UniqueBack=false}},
    }
  elseif c.image_uris then
    c.face=c.image_uris.normal:gsub('%?.*',''):gsub('normal',qual)..imagesuffix
    if cardName:lower():match('geralf') then
      c.face=c.image_uris.normal:gsub('%?.*',''):gsub('normal','png'):gsub('jpg','png')..imagesuffix
    end
  end

  local cardDat={
    Transform={posX=0,posY=0,posZ=0,rotX=0,rotY=0,rotZ=0,scaleX=1,scaleY=1,scaleZ=1},
    Name="Card",
    Nickname=cardName,
    Description=c.oracle,
    Memo=c.oracle_id,
    CardID=n*100,
    CustomDeck={[n]={FaceURL=c.face,BackURL=backURL,NumWidth=1,NumHeight=1,Type=0,BackIsHidden=true,UniqueBack=false}},
  }

  if backDat then
    cardDat.States={[2]=backDat}
  end
  return cardDat
end


function setOracle(c)local n='\n[b]'
  if c.power then
    n=n..c.power..'/'..c.toughness
  elseif c.loyalty then
    n=n..tostring(c.loyalty)
  else
    n=false
  end
  return c.oracle_text..(n and n..'[/b]'or'')
end

function debugPrint(txt)
  if debugMode then
    printToAll("[DEBUG] " .. (txt or "nil"), {r=1, g=1, b=0.2})
  end
end

--------------------------------------------------------------------------------
-- pie's manual "JSONdecode" for scryfall's "object":"card"
--------------------------------------------------------------------------------

normal_card_keys={
  'object',
  'id',
  'oracle_id',
  'name',
  'lang',
  'layout',
  'image_status',
  'image_uris',
  'mana_cost',
  'cmc',
  'type_line',
  'oracle_text',
  'loyalty',
  'power',
  'toughness',
  'loyalty',
  'legalities',
  'set',
  'rulings_uri',
  'prints_search_uri',
  'collector_number'
}

image_uris_keys={    -- "image_uris":{
  'small',
  'normal',
  'large',
  'png',
  'art_crop',
  'border_crop',
}

legalities_keys={    -- "legalities":{
  'standard',
  'future',
  'historic',
  'gladiator',
  'pioneer',
  'modern',
  'legacy',
  'pauper',
  'vintage',
  'penny',
  'commander',
  'brawl',
  'duel',
  'oldschool',
  'premodern',
}

related_card_keys={     -- "all_parts":[{"object":"related_card",
  'id',
  'component',
  'name',
  'type_line',
  'uri',
}

card_face_keys={        -- "card_faces":[{"object":"card_face",
  'name',
  'mana_cost',
  'cmc',
  'type_line',
  'oracle_text',
  'power',
  'toughness',
  'loyalty',
  'image_uris',
}

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
function JSONdecode(txt)
  local jsonType = txt:match('{\n?%s*"object":%s*"(%w+)"')

  -- not scryfall? use normal JSON.decode
  if not(jsonType == 'card' or jsonType == 'list') then
    if jsonType == "error" then
      local errMsg = txt:match('.*"details"%s*:%s*"([^"]*)"')
      error("Scryfall API error: " .. (errMsg or "unknown error"))
    else
      debugPrint("Unknown JSON type: " .. (jsonType or "~nil"))
    end
    return JSON.decode(txt)
  end

  ------------------------------------------------------------------------------
  -- parse list: extract each card, and parse it separately
  -- used when one wants to decode a whole list
  if jsonType=='list' then
    local txtBeginning = txt:sub(1,80)
    local nCards=txtBeginning:match('"total_cards":(%d+)')
    if nCards==nil then
      return JSON.decode(txt)
    end
    local cardStart=0
    local cardEnd=0
    local cardDats = {}
    for i=1,nCards do     -- could insert max number cards to parse here
      cardStart=string.find(txt,'{"object":"card"',cardEnd+1)
      cardEnd = findClosingBracket(txt,cardStart)
      local cardDat = JSONdecode(txt:sub(cardStart,cardEnd))
      table.insert(cardDats,cardDat)
    end
    local dat = {object="list",total_cards=nCards,data=cardDats}    --ignoring has_more...
    return dat
  end

  ------------------------------------------------------------------------------
  -- parse card

  txt=txt:gsub('}',',}')    -- comma helps parsing last element in an array

  local cardDat={}
  local all_parts_i=string.find(txt,'"all_parts":')
  local card_faces_i=string.find(txt,'"card_faces":')

  -- if all_parts exist
  if all_parts_i~=nil then
    local st=string.find(txt,'%[',all_parts_i)
    local en=findClosingBracket(txt,st)
    local all_parts_txt = txt:sub(all_parts_i,en)
    local all_parts={}
    -- remove all_parts snip from the main text
    txt=txt:sub(1,all_parts_i-1)..txt:sub(en+2,-1)
    -- parse all_parts_txt for each related_card
    st=1
    local cardN=0
    while st~=nil do
      st=string.find(all_parts_txt,'{"object":"related_card"',st)
      if st~=nil then
        cardN=cardN+1
        en=findClosingBracket(all_parts_txt,st)
        local related_card_txt=all_parts_txt:sub(st,en)
        st=en
        local s,e=1,1
        local related_card={}
        for i,key in ipairs(related_card_keys) do
          val,s=getKeyValue(related_card_txt,key,s)
          related_card[key]=val
        end
        table.insert(all_parts,related_card)
        if cardN>100 then break end   -- avoid inf loop if something goes strange
      end
      cardDat.all_parts=all_parts
    end
  end

  -- if card_faces exist
  if card_faces_i~=nil then
    local st=string.find(txt,'%[',card_faces_i)
    local en=findClosingBracket(txt,st)
    local card_faces_txt = txt:sub(card_faces_i,en)
    local card_faces={}
    -- remove card_faces snip from the main text
    txt=txt:sub(1,card_faces_i-1)..txt:sub(en+2,-1)

    -- parse card_faces_txt for each card_face
    st=1
    local cardN=0
    while st~=nil do
      st=string.find(card_faces_txt,'{"object":"card_face"',st)
      if st~=nil then
        cardN=cardN+1
        en=findClosingBracket(card_faces_txt,st)
        local card_face_txt=card_faces_txt:sub(st,en)
        st=en
        local s,e=1,1
        local card_face={}
        for i,key in ipairs(card_face_keys) do
          val,s=getKeyValue(card_face_txt,key,s)
          card_face[key]=val
        end
        table.insert(card_faces,card_face)
        if cardN>4 then break end   -- avoid inf loop if something goes strange
      end
      cardDat.card_faces=card_faces
    end
  end

  -- normal card (or what's left of it after removing card_faces and all_parts)
  st=1
  for i,key in ipairs(normal_card_keys) do
    val,st=getKeyValue(txt,key,st)
    cardDat[key]=val
  end

  return cardDat
end

--------------------------------------------------------------------------------
-- returns data for one card at a time from a scryfall's "object":"list"
function getNextCardDatFromList(txt,startHere)

  if startHere==nil then
    startHere=1
  end

  local cardStart=string.find(txt,'{"object":"card"',startHere)
  if cardStart==nil then
    -- print('error: no more cards in list')
    startHere=nil
    return nil,nil,nil
  end

  local cardEnd = findClosingBracket(txt,cardStart)
  if cardEnd==nil then
    -- print('error: no more cards in list')
    startHere=nil
    return nil,nil,nil
  end

  -- startHere is not a local variable, so it's possible to just do:
  -- getNextCardFromList(txt) and it will keep giving the next card or nil if there's no more
  startHere=cardEnd+1

  local cardDat = JSONdecode(txt:sub(cardStart,cardEnd))

  return cardDat,cardStart,cardEnd
end

--------------------------------------------------------------------------------
function findClosingBracket(txt,st)   -- find paired {} or []
  if st==nil then return nil end
  local ob,cb='{','}'
  local pattern='[{}]'
  if txt:sub(st,st)=='[' then
    ob,cb='[',']'
    pattern='[%[%]]'
  end
  local txti=st
  local nopen=1
  while nopen>0 do
    if txti==nil then return nil end
    txti=string.find(txt,pattern,txti+1)
    if txt:sub(txti,txti)==ob then
      nopen=nopen+1
    elseif txt:sub(txti,txti)==cb then
      nopen=nopen-1
    end
  end
  return txti
end

--------------------------------------------------------------------------------
function getKeyValue(txt,key,st)
  local str='"'..key..'":'
  local st=string.find(txt,str,st)
  local en=nil
  local value=nil
  if st~=nil then
    if key=='image_uris' then     -- special case for scryfall's image_uris table
      value={}
      local s=st
      for i,k in ipairs(image_uris_keys) do
        local val,s=getKeyValue(txt,k,s)
        value[k]=val
      end
      en=s
    elseif txt:sub(st+#str,st+#str)~='"' then      -- not a string
      en=string.find(txt,',"',st+#str+1)
      value=tonumber(txt:sub(st+#str,en-1))
    else                                           -- a string
      en=string.find(txt,'",',st+#str+1)
      value=txt:sub(st+#str+1,en-1):gsub('\\"','"'):gsub('\\n','\n'):gsub("\\u(%x%x%x%x)",function (x) return string.char(tonumber(x,16)) end)
    end
  end
  if type(value)=='string' then
    value=value:gsub(',}','}')    -- get rid of the previously inserted comma
  end
  return value,en
end