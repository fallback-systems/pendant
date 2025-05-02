# Run with: mix run scripts/seed_knowledge_base.ex

# This script seeds the knowledge base with sample data for testing
# It should be run on a development or test system to populate the database

alias Pendant.KnowledgeBase.Repo
alias Pendant.KnowledgeBase.Category
alias Pendant.KnowledgeBase.Article

IO.puts("Seeding knowledge base with sample data...")

# Create categories
{:ok, first_aid} = Repo.insert(%Category{
  name: "First Aid",
  description: "Medical emergency procedures and treatments",
  icon: "medical-kit"
})

{:ok, water} = Repo.insert(%Category{
  name: "Water",
  description: "Finding and purifying water in emergency situations",
  icon: "water"
})

{:ok, shelter} = Repo.insert(%Category{
  name: "Shelter",
  description: "Building and finding emergency shelter",
  icon: "home"
})

{:ok, food} = Repo.insert(%Category{
  name: "Food",
  description: "Finding and preparing food in the wild",
  icon: "utensils"
})

{:ok, navigation} = Repo.insert(%Category{
  name: "Navigation",
  description: "Finding your way without modern technology",
  icon: "compass"
})

# Create articles
Repo.insert!(%Article{
  title: "CPR Procedure",
  content: """
  # CPR Procedure

  Cardiopulmonary resuscitation (CPR) is a lifesaving technique useful in many emergencies, such as a heart attack or near drowning, in which someone's breathing or heartbeat has stopped.

  ## Adult CPR
  
  1. **Check the scene for safety**
  2. **Call for help** - Shout for help or call emergency services if possible
  3. **Check for responsiveness** - Tap the person and ask loudly, "Are you OK?"
  4. **Check for breathing** - Look, listen, and feel for breathing for 5-10 seconds
  5. **Begin chest compressions**:
     - Position hands in the center of the chest
     - Compress at least 2 inches deep
     - Compress at a rate of 100-120 compressions per minute
     - Allow complete chest recoil between compressions
  6. **Provide rescue breaths** (if trained):
     - Open the airway using head-tilt, chin-lift
     - Pinch the nose and create a seal over their mouth with yours
     - Give 2 breaths (1 second each)
     - Watch for chest rise
  7. **Continue CPR** - 30 compressions followed by 2 breaths
  8. **Use AED as soon as available**
  9. **Continue until help arrives** or the person shows signs of life

  Remember: Even hands-only CPR (compression only, no breaths) is effective.
  """,
  summary: "Step-by-step guide to performing CPR in emergency situations",
  category_id: first_aid.id,
  importance: 5,
  tags: "cpr,resuscitation,heart attack,breathing,medical,emergency"
})

Repo.insert!(%Article{
  title: "Treating Severe Bleeding",
  content: """
  # Treating Severe Bleeding

  Severe bleeding can be life-threatening and requires immediate treatment.

  ## Immediate Actions

  1. **Ensure safety** - Make sure you're not in danger
  2. **Apply direct pressure**:
     - Use a clean cloth, gauze, or clothing
     - Press firmly on the wound
     - If blood soaks through, add more material without removing the first layer
  3. **Elevate the wound** - If possible, raise the wound above the heart
  4. **Apply pressure to pressure points** - If direct pressure isn't working, apply pressure to the artery supplying the area
  5. **Use a tourniquet as last resort**:
     - Place 2-3 inches above the wound (not on a joint)
     - Tighten until bleeding stops
     - Note the time it was applied
     - Once applied, do not remove until medical help arrives

  ## Signs of Severe Blood Loss

  - Confusion or disorientation
  - Pale, cold, or clammy skin
  - Rapid breathing
  - Weak pulse
  - Decreasing consciousness

  ## After Bleeding Is Controlled

  - Keep the person warm
  - Do not give food or drink
  - Monitor for signs of shock
  - Get medical help as soon as possible
  """,
  summary: "How to control and treat severe bleeding in emergency situations",
  category_id: first_aid.id,
  importance: 5,
  tags: "bleeding,wounds,first aid,tourniquet,emergency,trauma"
})

Repo.insert!(%Article{
  title: "Water Purification Methods",
  content: """
  # Water Purification Methods

  Purifying water in emergency situations is critical to prevent waterborne diseases.

  ## Boiling

  **The most reliable method**:
  - Bring water to a rolling boil for 1 minute (3 minutes at elevations above 6,500 feet)
  - Let cool naturally
  - Improve taste by adding a pinch of salt per quart or by pouring water from one container to another several times

  ## Chemical Treatment

  **Using household bleach**:
  - Use regular, unscented chlorine bleach (5-6% sodium hypochlorite)
  - Add 2 drops per quart of clear water or 4 drops for cloudy water
  - Mix well and let stand for 30 minutes

  **Using iodine**:
  - Use 2% tincture of iodine
  - Add 5 drops per quart of clear water or 10 drops for cloudy water
  - Mix well and let stand for 30 minutes
  - Not recommended for pregnant women or people with thyroid problems

  ## Filtration

  **Improvised filters**:
  - Create a layered filter using cloth, sand, charcoal, and gravel
  - Pour water through multiple times
  - Still requires chemical treatment or boiling afterward

  ## Solar Disinfection (SODIS)

  - Fill clear plastic PET bottles 3/4 full
  - Shake vigorously for 20 seconds to oxygenate
  - Fill completely and cap
  - Place in direct sunlight for at least 6 hours (or 2 days if cloudy)
  - Effective against bacteria, viruses, and parasites

  ## When to Purify Water

  Always purify water from:
  - Rivers, lakes, and streams
  - Unknown sources
  - After disasters when municipal systems may be contaminated
  """,
  summary: "Different methods to make water safe for drinking in emergency situations",
  category_id: water.id,
  importance: 5,
  tags: "water,purification,boiling,filtration,emergency,survival,drinking"
})

Repo.insert!(%Article{
  title: "Finding Water in the Wild",
  content: """
  # Finding Water in the Wild

  Water is your most critical survival need. Here's how to find it in various environments.

  ## Universal Water Sources

  - **Rain**: Collect using tarps, containers, or plant leaves
  - **Dew**: Collect in early morning using cloth to absorb from plants/grass
  - **Solar still**: Dig a hole, place container in center, cover with plastic, place stone in center to create depression

  ## Desert Environments

  - Look for green vegetation, especially in low areas
  - Dry river beds: Dig in the outside bend of a curve, 1-2 feet deep
  - Follow animal tracks at dawn/dusk - they often lead to water
  - Cacti and certain desert plants store water
  - Canyon bottoms may have seasonal springs

  ## Forested Areas

  - Follow drainage paths downhill
  - Look for animal trails that converge
  - Find areas with denser, greener vegetation
  - Valleys and low points often contain water
  - Look for exposed rock faces - water may seep from cracks

  ## Coastal Areas

  - Dig a hole above the high tide line to find filtrated freshwater
  - Collect rainfall in clean containers
  - Look for freshwater streams emptying into the ocean

  ## Warning Signs of Unsafe Water

  - Abnormal color, odor, or taste
  - Dead fish or animals nearby
  - Excessive algae or plant growth
  - Foamy or oily surface
  - Industrial or agricultural areas nearby

  **Important**: Always purify any water found in the wild before drinking!
  """,
  summary: "Techniques for locating water sources in different wilderness environments",
  category_id: water.id,
  importance: 5,
  tags: "water,wilderness,survival,foraging,emergency,dehydration"
})

IO.puts("Knowledge base seeded successfully!")