router.get("/users", handler)
app.post("/pay", handler)
@Get("/admin")
export async function upd(){ await prisma.user.update({where:{id}}) }
const K = "sk_live_FIXTURE_PLACEHOLDER_NOT_REAL"
enum Role { ADMIN }
